//
//  PlaybackQuality.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Streaming quality preference.
public enum AudioQuality: String, Sendable, Hashable, Identifiable, CaseIterable, Codable {
    case auto
    case high
    case medium
    case low

    public var id: String { rawValue }
}

/// Download quality preference.
public enum DownloadQuality: String, Sendable, Hashable, Identifiable, CaseIterable, Codable {
    case auto
    case high
    case standard

    public var id: String { rawValue }
}
