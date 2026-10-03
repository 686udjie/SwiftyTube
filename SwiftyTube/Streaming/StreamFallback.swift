//
//  StreamFallback.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Loop behavior for `StreamFallback.resolveFirstValid`.
public struct FallbackPolicy: Sendable {
    /// Return a fresh cache entry, no network.
    public var useCache: Bool
    /// Store hits in the cache.
    public var storeInCache: Bool
    /// Validate URLs (honor `skipValidation`).
    public var validateStreams: Bool
    /// Expired-cache fallback on total failure.
    public var expiredCacheFallback: Bool
    /// Prefer AAC, keep first non-AAC aside.
    public var preferAAC: Bool

    public init(
        useCache: Bool,
        storeInCache: Bool,
        validateStreams: Bool,
        expiredCacheFallback: Bool,
        preferAAC: Bool
    ) {
        self.useCache = useCache
        self.storeInCache = storeInCache
        self.validateStreams = validateStreams
        self.expiredCacheFallback = expiredCacheFallback
        self.preferAAC = preferAAC
    }

    /// Playback: cache, validate, expired-cache fallback.
    public static let playback = FallbackPolicy(
        useCache: true,
        storeInCache: true,
        validateStreams: true,
        expiredCacheFallback: true,
        preferAAC: false
    )

    /// Download: no cache, validate, AAC preferred with non-AAC fallback.
    public static let download = FallbackPolicy(
        useCache: false,
        storeInCache: false,
        validateStreams: true,
        expiredCacheFallback: false,
        preferAAC: true
    )
}

/// What to resolve, in what order, how to behave.
public struct StreamResolveRequest: Sendable {
    public var videoId: String
    public var chain: [FallbackClient]
    public var options: StreamResolveOptions
    public var policy: FallbackPolicy

    public init(
        videoId: String,
        chain: [FallbackClient] = ClientFallbackChain.preferred,
        options: StreamResolveOptions = .default,
        policy: FallbackPolicy = .playback
    ) {
        self.videoId = videoId
        self.chain = chain
        self.options = options
        self.policy = policy
    }

    /// Playback request for a video.
    public static func playback(
        videoId: String,
        options: StreamResolveOptions = .default
    ) -> StreamResolveRequest {
        StreamResolveRequest(videoId: videoId, chain: ClientFallbackChain.preferred, options: options, policy: .playback)
    }

    /// Download request for a video.
    public static func download(
        videoId: String,
        options: StreamResolveOptions = .default
    ) -> StreamResolveRequest {
        var options = options
        options.forDownload = true
        return StreamResolveRequest(
            videoId: videoId,
            chain: ClientFallbackChain.forDownload,
            options: options,
            policy: .download
        )
    }
}

/// Muxed URL or video+audio pair.
public enum VideoStream: Sendable {
    case muxed(String)
    case split(video: String, audio: String, duration: Int?)
}

/// Shared fallback loops (player wiring stays in apps).
public enum StreamFallback: Sendable {
    /// First valid stream across the chain. PoTokens minted lazily.
    public static func resolveFirstValid(
        _ request: StreamResolveRequest,
        using innerTube: InnerTubeClient,
        cache: StreamCache = .shared,
        providers: StreamResolveProviders = .none
    ) async throws -> PlaybackResult {
        if request.policy.useCache, let cached = await cache.get(videoId: request.videoId) {
            return cached
        }

        var poTokenTask: Task<PoTokenResult?, Never>?
        defer { poTokenTask?.cancel() }

        var lastError: Error?
        var nonAACFallback: PlaybackResult?

        for entry in request.chain {
            var options = request.options
            if entry.client.useWebPoTokens, let provider = providers.poTokenProvider {
                if poTokenTask == nil {
                    let videoId = request.videoId
                    poTokenTask = Task { await provider(videoId) }
                }
                options.poToken = await poTokenTask?.value?.playerRequestPoToken ?? options.poToken
                options.streamingDataPoToken = await poTokenTask?.value?.streamingDataPoToken
                    ?? options.streamingDataPoToken
            }

            do {
                let result = try await StreamResolver.resolve(
                    videoId: request.videoId,
                    client: entry.client,
                    using: innerTube,
                    options: options,
                    providers: providers
                )

                if request.policy.validateStreams, !entry.skipValidation {
                    let valid = await StreamResolver.validateStream(
                        url: result.streamUrl,
                        onStreamRejection: providers.onStreamRejection
                    )
                    guard valid else {
                        lastError = StreamError.validationFailed(result.clientName)
                        SwiftyTubeLog.debug("\(result.clientName) Range validation failed, trying next")
                        continue
                    }
                }

                if request.policy.preferAAC {
                    let mime = result.mimeType.lowercased()
                    if !(mime.contains("mp4a") || mime.contains("aac")) {
                        SwiftyTubeLog.debug("\(result.clientName) returned non-AAC (\(result.mimeType))")
                        if nonAACFallback == nil {
                            nonAACFallback = result
                        }
                        continue
                    }
                } else if request.policy.storeInCache {
                    await cache.set(videoId: request.videoId, result: result)
                }
                return result
            } catch {
                lastError = error
                SwiftyTubeLog.error("\(entry.client.clientName) failed: \(error.localizedDescription)")
            }
        }

        if request.policy.preferAAC, let fallback = nonAACFallback {
            SwiftyTubeLog.debug("No AAC stream found - falling back to \(fallback.mimeType)")
            return fallback
        }

        if request.policy.expiredCacheFallback,
           let expired = await cache.getExpired(videoId: request.videoId) {
            SwiftyTubeLog.notice("All clients failed for \(request.videoId), falling back to expired cache")
            return expired
        }
        throw lastError ?? StreamError.allClientsFailed
    }

    /// Muxed URL or split pair. Throws `noSuitableFormat`.
    public static func resolveVideo(
        _ request: StreamResolveRequest,
        using innerTube: InnerTubeClient,
        providers: StreamResolveProviders = .none
    ) async throws -> VideoStream {
        var lastError: Error?

        for entry in request.chain {
            do {
                let signatureTimestamp: Int?
                if entry.client.useSignatureTimestamp {
                    signatureTimestamp = await providers.signatureTimestamp?()
                } else {
                    signatureTimestamp = nil
                }

                let response: PlayerResponse = try await innerTube.playerResponse(
                    videoId: request.videoId,
                    client: entry.client,
                    options: PlayerRequestOptions(
                        signatureTimestamp: signatureTimestamp,
                        poToken: request.options.poToken
                    )
                )

                guard let streamingData = response.streamingData else {
                    continue
                }

                let allFormats = (streamingData.formats ?? []) + (streamingData.adaptiveFormats ?? [])

                if let muxed = FormatSelector.bestVideoFormat(from: allFormats),
                   let url = muxed.url {
                    return .muxed(url)
                }

                if let video = FormatSelector.bestVideoOnlyFormat(from: allFormats),
                   let videoURL = video.url,
                   let audio = FormatSelector.bestAudioFormat(
                       from: allFormats,
                       preference: request.options.audioQuality
                   ),
                   let audioURL = try? await resolveFormatURL(audio, providers: providers) {
                    let duration = response.videoDetails?.lengthSeconds.flatMap(Int.init)
                    return .split(video: videoURL, audio: audioURL, duration: duration)
                }
            } catch {
                lastError = error
                SwiftyTubeLog.error("Video resolution failed for \(entry.client.clientName): \(error)")
            }
        }

        throw lastError ?? StreamError.noSuitableFormat
    }

    /// Resolves a single format's stream URL, going through the cipher if needed.
    public static func resolveFormatURL(
        _ format: Format,
        providers: StreamResolveProviders = .none
    ) async throws -> String {
        if let url = format.url, !url.isEmpty { return url }
        if let cipherText = format.signatureCipher ?? format.cipher,
           let cipherURL = providers.cipherURL,
           let playerJs = providers.playerJs {
            return try await cipherURL(cipherText, await playerJs())
        }
        throw StreamError.noStreamUrl
    }

    /// mpv EDL for separate DASH tracks.
    public static func combineVideoAndAudio(videoURL: String, audioURL: String, duration: Int?) -> String {
        let lengthParam = duration.map { ",length=\($0)" } ?? ""
        let video = "%\(videoURL.utf8.count)%\(videoURL)\(lengthParam)"
        let audio = "%\(audioURL.utf8.count)%\(audioURL)\(lengthParam)"
        return "edl://!new_stream;!no_clip;!no_chapters;\(video);!new_stream;!no_clip;!no_chapters;\(audio)"
    }
}
