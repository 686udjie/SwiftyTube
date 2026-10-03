//
//  StreamResolver.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Per-call knobs for `StreamResolver.resolve`.
public struct StreamResolveOptions: Sendable {
    /// PoToken for web clients (playerRequestPoToken).
    public var poToken: String?
    /// PoToken appended to stream URLs (`&pot=`).
    public var streamingDataPoToken: String?
    /// Caller-preferred format (used when still present in the response).
    public var preferredFormat: Format?
    public var forDownload: Bool
    public var audioQuality: AudioQuality
    public var downloadQuality: DownloadQuality

    public init(
        poToken: String? = nil,
        streamingDataPoToken: String? = nil,
        preferredFormat: Format? = nil,
        forDownload: Bool = false,
        audioQuality: AudioQuality = .auto,
        downloadQuality: DownloadQuality = .high
    ) {
        self.poToken = poToken
        self.streamingDataPoToken = streamingDataPoToken
        self.preferredFormat = preferredFormat
        self.forDownload = forDownload
        self.audioQuality = audioQuality
        self.downloadQuality = downloadQuality
    }

    public static let `default` = StreamResolveOptions()
}

/// Optional cipher/PoToken hooks; nil steps are skipped.
public struct StreamResolveProviders: Sendable {
    /// Player.js signature timestamp for clients with `useSignatureTimestamp`.
    public var signatureTimestamp: (@Sendable () async -> Int?)?
    /// (cipherText, playerJs) → URL.
    public var cipherURL: (@Sendable (String, String) async throws -> String)?
    /// Fetches player.js content for cipher resolution.
    public var playerJs: (@Sendable () async throws -> String)?
    /// Called when a stream URL gets HTTP 403 during validation.
    public var onStreamRejection: (@Sendable () async -> Void)?
    /// Tokens per videoId; nil proceeds tokenless.
    public var poTokenProvider: (@Sendable (String) async -> PoTokenResult?)?
    /// Persist hook per resolve. Never throws.
    public var resolvedFormatHandler: (@Sendable (ResolvedFormatInfo) async -> Void)?

    public init(
        signatureTimestamp: (@Sendable () async -> Int?)? = nil,
        cipherURL: (@Sendable (String, String) async throws -> String)? = nil,
        playerJs: (@Sendable () async throws -> String)? = nil,
        onStreamRejection: (@Sendable () async -> Void)? = nil,
        poTokenProvider: (@Sendable (String) async -> PoTokenResult?)? = nil,
        resolvedFormatHandler: (@Sendable (ResolvedFormatInfo) async -> Void)? = nil
    ) {
        self.signatureTimestamp = signatureTimestamp
        self.cipherURL = cipherURL
        self.playerJs = playerJs
        self.onStreamRejection = onStreamRejection
        self.poTokenProvider = poTokenProvider
        self.resolvedFormatHandler = resolvedFormatHandler
    }

    public static let none = StreamResolveProviders()
}

/// Format facts for app persistence.
public struct ResolvedFormatInfo: Sendable {
    public var videoId: String
    public var itag: Int
    public var mimeType: String
    public var codecs: String
    public var bitrate: Int
    public var contentLength: Int64
    public var loudnessDb: Double?
    public var playbackUrl: String?

    public init(
        videoId: String,
        itag: Int,
        mimeType: String,
        codecs: String,
        bitrate: Int,
        contentLength: Int64,
        loudnessDb: Double?,
        playbackUrl: String?
    ) {
        self.videoId = videoId
        self.itag = itag
        self.mimeType = mimeType
        self.codecs = codecs
        self.bitrate = bitrate
        self.contentLength = contentLength
        self.loudnessDb = loudnessDb
        self.playbackUrl = playbackUrl
    }
}

// One client, one /player call.
public enum StreamResolver: Sendable {
    /// Resolves the best stream URL for a video with a specific client.
    public static func resolve(
        videoId: String,
        client: YouTubeClient,
        using innerTube: InnerTubeClient,
        options: StreamResolveOptions = .default,
        providers: StreamResolveProviders = .none
    ) async throws -> PlaybackResult {
        SwiftyTubeLog.debug("Resolving videoId=\(videoId) client=\(client.clientName) v\(client.clientVersion)")

        let signatureTimestamp: Int?
        if client.useSignatureTimestamp {
            signatureTimestamp = await providers.signatureTimestamp?()
            if let timestamp = signatureTimestamp {
                SwiftyTubeLog.debug("Using signatureTimestamp=\(timestamp)")
            }
        } else {
            signatureTimestamp = nil
        }

        let response: PlayerResponse = try await innerTube.playerResponse(
            videoId: videoId,
            client: client,
            options: PlayerRequestOptions(
                signatureTimestamp: signatureTimestamp,
                poToken: options.poToken
            )
        )

        guard let playabilityStatus = response.playabilityStatus else {
            throw StreamError.unplayable(reason: "No playability status in response")
        }

        if playabilityStatus.status != "OK" {
            let reason = playabilityStatus.reason ?? "Unknown"
            // Tolerate non-OK clients that still return formats.
            guard client.skipPlayerResponseValidation else {
                SwiftyTubeLog.error("Not playable: status=\(playabilityStatus.status ?? "?") reason=\(reason)")
                throw StreamError.unplayable(reason: reason)
            }
            SwiftyTubeLog.notice("Status=\(playabilityStatus.status ?? "?") (\(reason)) - attempting formats anyway")
        } else {
            SwiftyTubeLog.debug("Playable: status=OK")
        }

        guard let streamingData = response.streamingData else {
            throw StreamError.noStreams
        }

        let adaptiveFormats = streamingData.adaptiveFormats ?? []
        SwiftyTubeLog.debug(
            "Got \(adaptiveFormats.count) adaptive formats, expiresIn=\(streamingData.expiresInSeconds ?? "?")s"
        )

        let allFormats = (streamingData.formats ?? []) + adaptiveFormats
        let maxVideoHeight = allFormats.compactMap { $0.height }.max() ?? 0
        let hasVideoContent = maxVideoHeight >= 480
        SwiftyTubeLog.debug(
            "hasVideoContent=\(hasVideoContent) (maxVideoHeight=\(maxVideoHeight), " +
                "video formats: \(allFormats.filter { $0.width != nil }.count))"
        )

        let selectedFormat: Format
        if let preferred = options.preferredFormat,
           adaptiveFormats.contains(where: { $0.itag == preferred.itag }) {
            selectedFormat = preferred
            SwiftyTubeLog.debug("Using preferred format itag=\(preferred.itag ?? 0)")
        } else if options.forDownload,
                  let downloadFormat = FormatSelector.bestDownloadFormat(
                      from: allFormats,
                      downloadQuality: options.downloadQuality
                  ) {
            selectedFormat = downloadFormat
        } else if let best = FormatSelector.bestAudioFormat(
            from: allFormats,
            preference: options.audioQuality
        ) {
            selectedFormat = best
        } else {
            let formatInfos = allFormats.map { format in
                "itag=\(format.itag ?? 0) mime=\(format.mimeType ?? "?") audio=\(format.audioChannels != nil) " +
                    "url=\(format.url != nil) cipher=\(format.signatureCipher != nil || format.cipher != nil)"
            }
            SwiftyTubeLog.error("No suitable format. Formats: \(formatInfos.joined(separator: ", "))")
            throw StreamError.noSuitableFormat
        }

        let streamUrl: String
        if let url = selectedFormat.url, !url.isEmpty {
            streamUrl = url
            SwiftyTubeLog.debug("Direct URL: \(streamUrl.prefix(120))...")
        } else if let cipherText = selectedFormat.signatureCipher ?? selectedFormat.cipher {
            SwiftyTubeLog.debug("Format requires cipher deobfuscation")
            guard let cipherURL = providers.cipherURL, let playerJs = providers.playerJs else {
                throw StreamError.noStreamUrl
            }
            let playerJsContent = try await playerJs()
            streamUrl = try await cipherURL(cipherText, playerJsContent)
            SwiftyTubeLog.debug("Resolved cipher URL: \(streamUrl.prefix(120))...")
        } else {
            throw StreamError.noStreamUrl
        }

        var finalStreamUrl = streamUrl
        if let pot = options.streamingDataPoToken, client.useWebPoTokens {
            finalStreamUrl += "&pot=" + Self.encodeQueryValue(pot)
            SwiftyTubeLog.debug("Appended &pot= to stream URL")
        }

        let videoDetails = response.videoDetails
        let duration = videoDetails?.lengthSeconds.flatMap(Int.init)
        let musicVideoType = videoDetails?.musicVideoType

        let muxedStreamUrl: String? = {
            guard let videoFormat = FormatSelector.bestVideoFormat(from: allFormats),
                  let url = videoFormat.url, !url.isEmpty else {
                return nil
            }
            var muxed = url
            if let pot = options.streamingDataPoToken, client.useWebPoTokens {
                muxed += "&pot=" + Self.encodeQueryValue(pot)
            }
            return muxed
        }()

        let result = PlaybackResult(
            streamUrl: finalStreamUrl,
            itag: selectedFormat.itag ?? 0,
            mimeType: selectedFormat.mimeType ?? "",
            bitrate: selectedFormat.bitrate ?? 0,
            audioQuality: selectedFormat.audioQuality ?? "",
            videoId: videoDetails?.videoId ?? videoId,
            title: videoDetails?.title,
            author: videoDetails?.author,
            duration: duration,
            expiresInSeconds: streamingData.expiresInSeconds.flatMap(Int.init) ?? 0,
            clientName: client.clientName,
            musicVideoType: musicVideoType,
            hasVideoContent: hasVideoContent,
            muxedStreamUrl: muxedStreamUrl,
            loudnessDb: selectedFormat.loudnessDb
        )
        SwiftyTubeLog.debug("musicVideoType=\(musicVideoType ?? "nil")")

        if let duration, let resolvedVideoId = videoDetails?.videoId {
            DurationCache.set(resolvedVideoId, duration)
        }

        await providers.resolvedFormatHandler?(ResolvedFormatInfo(
            videoId: result.videoId,
            itag: result.itag,
            mimeType: result.mimeType,
            codecs: selectedFormat.codec,
            bitrate: result.bitrate,
            contentLength: (selectedFormat.contentLength as NSString?)?.longLongValue ?? 0,
            loudnessDb: result.loudnessDb,
            playbackUrl: response.playbackTracking?.videostatsPlaybackUrl?.baseUrl
        ))

        SwiftyTubeLog.debug(
            "Result: title=\"\(result.title ?? "?")\" author=\"\(result.author ?? "?")\" " +
                "itag=\(result.itag) quality=\(result.audioQuality) bitrate=\(result.bitrate)"
        )

        return result
    }

    /// Query-escape incl. +, =, &, /.
    static func encodeQueryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    /// 1 KiB Range GET check.
    public static func validateStream(
        url: String,
        session: URLSession = .shared,
        onStreamRejection: (@Sendable () async -> Void)? = nil
    ) async -> Bool {
        guard let url = URL(string: url) else {
            SwiftyTubeLog.error("Invalid URL for validation")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")

        do {
            let (_, httpResponse) = try await HttpClient.data(for: request, session: session)
            let valid = (200 ... 299).contains(httpResponse.statusCode)
            if !valid {
                SwiftyTubeLog.debug("Range validation: status=\(httpResponse.statusCode) valid=false")
            }
            if httpResponse.statusCode == 403 {
                await onStreamRejection?()
            }
            return valid
        } catch {
            SwiftyTubeLog.error("Range validation failed: \(error.localizedDescription)")
            return false
        }
    }
}
