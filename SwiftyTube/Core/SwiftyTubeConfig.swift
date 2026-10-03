//
//  SwiftyTubeConfig.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Static setup. Per-request overrides (client, locale) go on each method.
public struct SwiftyTubeConfig: Sendable {
    public var service: YouTubeService
    public var defaultClient: YouTubeClient
    public var defaultLocale: YouTubeLocale
    public var timeoutSeconds: TimeInterval
    public var acceptLanguage: String

    public init(
        service: YouTubeService,
        defaultClient: YouTubeClient,
        defaultLocale: YouTubeLocale = .default,
        timeoutSeconds: TimeInterval = 30,
        acceptLanguage: String = "en-US,en;q=0.9"
    ) {
        self.service = service
        self.defaultClient = defaultClient
        self.defaultLocale = defaultLocale
        self.timeoutSeconds = timeoutSeconds
        self.acceptLanguage = acceptLanguage
    }

    /// YouTube Music host + WEB_REMIX.
    public static let music = SwiftyTubeConfig(
        service: .music,
        defaultClient: .webRemix
    )

    /// Main YouTube host + WEB.
    public static let youtube = SwiftyTubeConfig(
        service: .youtube,
        defaultClient: .web
    )
}
