//
//  PlaybackResult.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Result of a successful stream resolution.
public struct PlaybackResult: Sendable, Hashable, Codable {
    public let streamUrl: String
    public let itag: Int
    public let mimeType: String
    public let bitrate: Int
    public let audioQuality: String
    public let videoId: String
    public let title: String?
    public let author: String?
    public let duration: Int?
    public let expiresInSeconds: Int
    public let clientName: String
    public let musicVideoType: String?
    /// Has video dimensions.
    public let hasVideoContent: Bool
    /// Combined audio-video stream URL for instant toggling without reloads.
    public let muxedStreamUrl: String?
    /// Loudness of the selected stream (LUFS) for normalization.
    public let loudnessDb: Double?

    public init(
        streamUrl: String,
        itag: Int,
        mimeType: String,
        bitrate: Int,
        audioQuality: String,
        videoId: String,
        title: String?,
        author: String?,
        duration: Int?,
        expiresInSeconds: Int,
        clientName: String,
        musicVideoType: String?,
        hasVideoContent: Bool,
        muxedStreamUrl: String?,
        loudnessDb: Double?
    ) {
        self.streamUrl = streamUrl
        self.itag = itag
        self.mimeType = mimeType
        self.bitrate = bitrate
        self.audioQuality = audioQuality
        self.videoId = videoId
        self.title = title
        self.author = author
        self.duration = duration
        self.expiresInSeconds = expiresInSeconds
        self.clientName = clientName
        self.musicVideoType = musicVideoType
        self.hasVideoContent = hasVideoContent
        self.muxedStreamUrl = muxedStreamUrl
        self.loudnessDb = loudnessDb
    }
}
