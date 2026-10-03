//
//  FormatSelector.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

// Best-format picks. Audio score: quality, channels, codec, bitrate.
// Video prefers H.264 (simulator can't decode VP9).
public enum FormatSelector: Sendable {
    /// Audio-only first, then combined with audio. Nil if none.
    public static func audioBearingFormats(_ formats: [Format]) -> [Format]? {
        var audioFormats = formats.filter { $0.isAudioOnly }
        if audioFormats.isEmpty {
            SwiftyTubeLog.debug("No audio-only formats found - trying combined formats with audio track")
            audioFormats = formats.filter { $0.audioChannels != nil }
        }
        guard !audioFormats.isEmpty else {
            SwiftyTubeLog.debug("No formats with audio track found in \(formats.count) total formats")
            return nil
        }
        return audioFormats
    }

    /// Prefers H.264 (avc/mp4) for compatibility, falling back to the full pool.
    public static func h264PreferredPool(_ formats: [Format], kind: String) -> [Format] {
        let h264 = formats.filter {
            $0.codec.lowercased().contains("avc") || $0.mimeType?.lowercased().contains("mp4") == true
        }
        if h264.isEmpty {
            SwiftyTubeLog.debug("No H.264 \(kind) format; falling back to any \(kind) format")
        }
        return h264.isEmpty ? formats : h264
    }

    /// Best audio format, optionally restricted to the user's quality tier first.
    public static func bestAudioFormat(from formats: [Format], preference: AudioQuality = .auto) -> Format? {
        guard !formats.isEmpty else {
            SwiftyTubeLog.debug("No formats to select from")
            return nil
        }

        guard var audioFormats = audioBearingFormats(formats) else { return nil }

        if preference != .auto {
            let tier = Self.qualityTier(for: preference)
            let tierFormats = audioFormats.filter { Self.qualityRank($0.audioQuality) == tier }
            if !tierFormats.isEmpty {
                SwiftyTubeLog.debug("Preferring \(preference.rawValue) tier: \(tierFormats.count) format(s)")
                audioFormats = tierFormats
            } else {
                SwiftyTubeLog.debug("No \(preference.rawValue)-tier format, using best available")
            }
        }

        SwiftyTubeLog.debug("Selecting from \(audioFormats.count) audio-bearing formats")

        let selected = audioFormats.max { a, b in
            formatScore(a) < formatScore(b)
        }

        if let selected {
            SwiftyTubeLog.debug(
                "Selected: itag=\(selected.itag ?? 0) quality=\(selected.audioQuality ?? "?")" +
                    " channels=\(selected.audioChannels ?? 0) codec=\(selected.codec)" +
                    " bitrate=\(selected.bitrate ?? 0)"
            )
        } else {
            SwiftyTubeLog.debug("No format could be selected")
        }

        return selected
    }

    /// Maps the user-facing quality preference to the format quality tier.
    private static func qualityTier(for preference: AudioQuality) -> Int {
        switch preference {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .auto: return 0
        }
    }

    /// Maps a format's `AUDIO_QUALITY_*` string to a comparable tier.
    static func qualityRank(_ quality: String?) -> Int {
        switch quality {
        case "AUDIO_QUALITY_HIGH": return 3
        case "AUDIO_QUALITY_MEDIUM": return 2
        case "AUDIO_QUALITY_LOW": return 1
        default: return 0
        }
    }

    /// Best audio for downloads. `.standard` caps near the target, picks smallest.
    public static func bestDownloadFormat(
        from formats: [Format],
        downloadQuality: DownloadQuality = .high,
        standardTargetBitrate: Int = 96_000
    ) -> Format? {
        guard !formats.isEmpty else {
            SwiftyTubeLog.debug("No formats to select from (download)")
            return nil
        }

        guard let audioFormats = audioBearingFormats(formats) else { return nil }

        // Prefer formats we can actually fetch (direct URL or cipher).
        let fetchable = audioFormats.filter {
            ($0.url?.isEmpty == false) || $0.signatureCipher != nil || $0.cipher != nil
        }
        let candidates = fetchable.isEmpty ? audioFormats : fetchable

        let aacFormats = candidates.filter { format in
            let codec = format.codec.lowercased()
            return codec.contains("mp4a") || codec.contains("aac")
        }

        var pool = aacFormats.isEmpty ? candidates : aacFormats
        SwiftyTubeLog.debug(
            "Download pool: \(pool.count) format(s)\(aacFormats.isEmpty ? " (no AAC, falling back to Opus)" : " (AAC preferred)")"
        )

        if downloadQuality == .standard {
            let capped = pool.filter { ($0.bitrate ?? standardTargetBitrate) <= standardTargetBitrate + 32_000 }
            if !capped.isEmpty {
                pool = capped
            }
        }

        let selected: Format?
        if downloadQuality == .standard {
            selected = pool.min { ($0.bitrate ?? Int.max) < ($1.bitrate ?? Int.max) }
        } else {
            selected = pool.max { formatScore($0) < formatScore($1) }
        }

        if let selected {
            SwiftyTubeLog.debug(
                "Download selected: itag=\(selected.itag ?? 0) codec=\(selected.codec) bitrate=\(selected.bitrate ?? 0)"
            )
        }

        return selected
    }

    private static func formatScore(_ format: Format) -> Int {
        let qualityScore = qualityRank(format.audioQuality) * 10_000
        let channelsScore = (format.audioChannels ?? 2) * 1_000
        let codecScore = scoreCodec(format.codec) * 100
        let bitrateScore = (format.bitrate ?? 0) / 1000
        return qualityScore + channelsScore + codecScore + bitrateScore
    }

    private static func scoreCodec(_ codec: String) -> Int {
        let lowercased = codec.lowercased()
        if lowercased.contains("opus") { return 2 }
        if lowercased.contains("mp4a") || lowercased.contains("aac") { return 1 }
        return 0
    }

    // MARK: - Video Format Selection

    /// Best muxed (video+audio) format, H.264 first.
    public static func bestVideoFormat(from formats: [Format]) -> Format? {
        guard !formats.isEmpty else {
            SwiftyTubeLog.debug("No formats to select from (video)")
            return nil
        }

        let muxedFormats = formats.filter {
            !$0.isAudioOnly
                && $0.width != nil && $0.height != nil
                && $0.audioChannels != nil
                && $0.url != nil
        }

        guard !muxedFormats.isEmpty else {
            SwiftyTubeLog.debug("No muxed (audio+video) formats found in \(formats.count) total formats")
            return nil
        }

        SwiftyTubeLog.debug("Selecting from \(muxedFormats.count) muxed video formats")

        let pool = h264PreferredPool(muxedFormats, kind: "muxed")

        let selected = pool.max { a, b in
            videoFormatScore(a) < videoFormatScore(b)
        }

        if let selected {
            SwiftyTubeLog.debug(
                "Selected video: itag=\(selected.itag ?? 0) resolution=\(selected.width ?? 0)x\(selected.height ?? 0) " +
                    "codec=\(selected.codec) bitrate=\(selected.bitrate ?? 0)"
            )
        }

        return selected
    }

    /// Best DASH video-only format.
    public static func bestVideoOnlyFormat(from formats: [Format]) -> Format? {
        guard !formats.isEmpty else {
            SwiftyTubeLog.debug("No formats to select from (video-only)")
            return nil
        }

        let videoOnlyFormats = formats.filter {
            !$0.isAudioOnly
                && $0.width != nil && $0.height != nil
                && $0.audioChannels == nil
                && $0.url != nil
        }

        guard !videoOnlyFormats.isEmpty else {
            SwiftyTubeLog.debug("No video-only formats found in \(formats.count) total formats")
            return nil
        }

        let poolBase = h264PreferredPool(videoOnlyFormats, kind: "video-only")

        let capped = poolBase.filter { ($0.height ?? 0) <= 720 }
        let pool = capped.isEmpty ? poolBase : capped
        if capped.isEmpty {
            SwiftyTubeLog.debug("No video-only format ≤720p; using higher-resolution pool")
        }

        let selected = pool.max { a, b in
            videoFormatScore(a) < videoFormatScore(b)
        }

        if let selected {
            SwiftyTubeLog.debug(
                "Selected video-only: itag=\(selected.itag ?? 0)"
                    + " resolution=\(selected.width ?? 0)x\(selected.height ?? 0)"
                    + " codec=\(selected.codec) bitrate=\(selected.bitrate ?? 0)"
            )
        }

        return selected
    }

    private static func videoFormatScore(_ format: Format) -> Int {
        let widthScore = (format.width ?? 0) * 10
        let heightScore = (format.height ?? 0) * 10
        let bitrateScore = (format.bitrate ?? 0) / 1000
        return widthScore + heightScore + bitrateScore
    }
}
