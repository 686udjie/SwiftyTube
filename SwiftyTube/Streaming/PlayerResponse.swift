//
//  PlayerResponse.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Top-level response from POST /player.
public struct PlayerResponse: Decodable, Sendable {
    public let responseContext: ResponseContext?
    public let playabilityStatus: PlayabilityStatus?
    public let streamingData: StreamingData?
    public let videoDetails: VideoDetails?
    public let playbackTracking: PlaybackTracking?

    /// Simplified status check.
    public var isPlayable: Bool {
        playabilityStatus?.status == "OK"
    }
}

public struct ResponseContext: Decodable, Sendable {
    public let serviceTrackingParams: [ServiceTrackingParam]?
}

public struct ServiceTrackingParam: Decodable, Sendable {
    public let service: String?
    public let params: [TrackingParam]?
}

public struct TrackingParam: Decodable, Sendable {
    public let key: String?
    public let value: String?
}

/// Playability information.
public struct PlayabilityStatus: Decodable, Sendable {
    public let status: String?
    public let reason: String?
}

/// Streaming data containing available formats.
public struct StreamingData: Decodable, Sendable {
    public let formats: [Format]?
    public let adaptiveFormats: [Format]?
    public let expiresInSeconds: String?

    public var expiresInSecondsValue: Int? {
        expiresInSeconds.flatMap { Int($0) }
    }
}

/// Individual stream format (audio or video).
public struct Format: Decodable, Sendable {
    public let itag: Int?
    public let url: String?
    public let mimeType: String?
    public let bitrate: Int?
    public let width: Int?
    public let height: Int?
    public let contentLength: String?
    public let quality: String?
    public let averageBitrate: Int?
    public let audioQuality: String?
    public let audioChannels: Int?
    public let approxDurationMs: String?
    public let loudnessDb: Double?
    public let lastModified: String?
    public let signatureCipher: String?
    public let cipher: String?

    public var isAudioOnly: Bool {
        width == nil
    }

    public var codec: String {
        guard let mimeType else { return "" }
        // Extract codec from e.g. "audio/webm; codecs=\"opus\""
        if let codecsRange = mimeType.range(of: "codecs=\"") {
            let afterPrefix = mimeType[codecsRange.upperBound...]
            if let endQuote = afterPrefix.firstIndex(of: "\"") {
                return String(afterPrefix[..<endQuote])
            }
        }
        return mimeType
    }
}

/// Video metadata.
public struct VideoDetails: Decodable, Sendable {
    public let videoId: String?
    public let title: String?
    public let author: String?
    public let channelId: String?
    public let lengthSeconds: String?
    public let musicVideoType: String?
    public let viewCount: String?
    public let thumbnail: ThumbnailInfo?
}

public struct ThumbnailInfo: Decodable, Sendable {
    public let thumbnails: [ThumbnailImage]?
}

public struct ThumbnailImage: Decodable, Sendable {
    public let url: String?
    public let width: Int?
    public let height: Int?
}

/// Playback tracking URLs.
public struct PlaybackTracking: Decodable, Sendable {
    public let videostatsPlaybackUrl: TrackingUrl?
    public let videostatsWatchtimeUrl: TrackingUrl?
}

public struct TrackingUrl: Decodable, Sendable {
    public let baseUrl: String?
}
