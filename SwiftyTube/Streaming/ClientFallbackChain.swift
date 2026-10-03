//
//  ClientFallbackChain.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Wrapper for a YouTubeClient with validation skip flag.
public struct FallbackClient: Sendable, Hashable {
    public let client: YouTubeClient
    public let skipValidation: Bool

    public init(client: YouTubeClient, skipValidation: Bool) {
        self.client = client
        self.skipValidation = skipValidation
    }
}

/// Clients to try in order; first valid URL wins.
public enum ClientFallbackChain: Sendable {
    /// Base chain - fast direct-URL clients first, token-backed web clients last.
    private static let base: [FallbackClient] = [
        FallbackClient(client: .visionOS, skipValidation: false),
        FallbackClient(client: .androidVr1_65_10, skipValidation: false),
        FallbackClient(client: .androidVr1_61_48, skipValidation: false),
        FallbackClient(client: .androidVr1_43_32, skipValidation: false),
        FallbackClient(client: .tvHtml5SimplyEmbedded, skipValidation: false),
        FallbackClient(client: .iOS, skipValidation: true),
        FallbackClient(client: .tvHtml5, skipValidation: false),
        FallbackClient(client: .mobile, skipValidation: false),
        FallbackClient(client: .webRemix, skipValidation: true)
    ]

    /// Fallback chain for playback.
    public static var preferred: [FallbackClient] { base }

    /// Same order for downloads (validation stays on).
    public static var forDownload: [FallbackClient] { base }
}
