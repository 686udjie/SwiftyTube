//
//  YouTubeService.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// InnerTube host: `.music` (YouTube Music) or `.youtube` (YouTube).
public enum YouTubeService: String, Sendable, CaseIterable {
    case music
    case youtube

    public var baseURL: URL {
        switch self {
        case .music:
            return URL(string: "https://music.youtube.com/youtubei/v1/")!
        case .youtube:
            return URL(string: "https://www.youtube.com/youtubei/v1/")!
        }
    }

    public var origin: String {
        switch self {
        case .music:
            return "https://music.youtube.com"
        case .youtube:
            return "https://www.youtube.com"
        }
    }
}
