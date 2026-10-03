//
//  YouTubeClient.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Client identity per request.
public struct YouTubeClient: Sendable, Hashable, Codable {
    public let clientName: String
    public let clientVersion: String
    public let clientId: Int
    public let userAgent: String
    public let loginSupported: Bool
    public let useMusicPlayerEndpoint: Bool
    public let isEmbedded: Bool
    public let includeUserAgentInContext: Bool
    public let useSignatureTimestamp: Bool
    public let useWebPoTokens: Bool
    public let skipPlayerResponseValidation: Bool
    public let osName: String?
    public let osVersion: String?
    public let deviceMake: String?
    public let deviceModel: String?
    public let androidSdkVersion: String?
    public let platform: String?
    public let clientScreen: String?
    public let embedUrl: String?

    public init(
        clientName: String,
        clientVersion: String,
        clientId: Int,
        userAgent: String,
        loginSupported: Bool = false,
        useMusicPlayerEndpoint: Bool = false,
        isEmbedded: Bool = false,
        includeUserAgentInContext: Bool = false,
        useSignatureTimestamp: Bool = false,
        useWebPoTokens: Bool = false,
        skipPlayerResponseValidation: Bool = false,
        osName: String? = nil,
        osVersion: String? = nil,
        deviceMake: String? = nil,
        deviceModel: String? = nil,
        androidSdkVersion: String? = nil,
        platform: String? = nil,
        clientScreen: String? = nil,
        embedUrl: String? = nil
    ) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.clientId = clientId
        self.userAgent = userAgent
        self.loginSupported = loginSupported
        self.useMusicPlayerEndpoint = useMusicPlayerEndpoint
        self.isEmbedded = isEmbedded
        self.includeUserAgentInContext = includeUserAgentInContext
        self.useSignatureTimestamp = useSignatureTimestamp
        self.useWebPoTokens = useWebPoTokens
        self.skipPlayerResponseValidation = skipPlayerResponseValidation
        self.osName = osName
        self.osVersion = osVersion
        self.deviceMake = deviceMake
        self.deviceModel = deviceModel
        self.androidSdkVersion = androidSdkVersion
        self.platform = platform
        self.clientScreen = clientScreen
        self.embedUrl = embedUrl
    }

    public static let webUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"

    /// YouTube Music default.
    public static let webRemix = YouTubeClient(
        clientName: "WEB_REMIX",
        clientVersion: "1.20260707.12.00",
        clientId: 67,
        userAgent: webUserAgent,
        loginSupported: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )

    /// Main YouTube web default.
    public static let web = YouTubeClient(
        clientName: "WEB",
        clientVersion: "2.20260707.12.00",
        clientId: 1,
        userAgent: webUserAgent,
        loginSupported: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )

    /// Lightweight duration / metadata fetch, no cipher needed.
    public static let iOS = YouTubeClient(
        clientName: "IOS",
        clientVersion: "21.26.4",
        clientId: 5,
        userAgent: "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        includeUserAgentInContext: true,
        osName: "iPhone",
        osVersion: "18.3.2.22D82",
        deviceMake: "Apple",
        deviceModel: "iPhone16,2"
    )

    /// yt-dlp's default Android VR profile - stable direct URLs.
    public static let androidVr1_65_10 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.65.10",
        clientId: 28,
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        useMusicPlayerEndpoint: true,
        includeUserAgentInContext: true,
        osName: "Android",
        osVersion: "12L",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32"
    )

    public static let androidVr1_43_32 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.43.32",
        clientId: 28,
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3;" +
            " Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
        useMusicPlayerEndpoint: true,
        includeUserAgentInContext: true,
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32"
    )

    /// Newer Android VR version - direct URLs.
    public static let androidVr1_61_48 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.61.48",
        clientId: 28,
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3;" +
            " Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
        useMusicPlayerEndpoint: true,
        includeUserAgentInContext: true,
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32"
    )

    public static let tvHtml5 = YouTubeClient(
        clientName: "TVHTML5",
        clientVersion: "7.20260707.07.00",
        clientId: 7,
        userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko)," +
            " Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)",
        loginSupported: true,
        includeUserAgentInContext: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )

    public static let visionOS = YouTubeClient(
        clientName: "VISIONOS",
        clientVersion: "0.1",
        clientId: 101,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
        useMusicPlayerEndpoint: true,
        skipPlayerResponseValidation: true,
        osName: "VISION_OS",
        osVersion: "1.3",
        deviceMake: "Apple",
        deviceModel: "RealityDevice14,1",
        platform: "MOBILE"
    )

    /// Late fallback; needs platform attestation.
    public static let mobile = YouTubeClient(
        clientName: "ANDROID",
        clientVersion: "21.26.364",
        clientId: 3,
        userAgent: "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip",
        includeUserAgentInContext: true,
        osName: "Android",
        osVersion: "11",
        androidSdkVersion: "30"
    )

    /// Embedded player; bypasses age restriction without login.
    public static let tvHtml5SimplyEmbedded = YouTubeClient(
        clientName: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
        clientVersion: "2.0",
        clientId: 85,
        userAgent: tvHtml5.userAgent,
        isEmbedded: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true,
        embedUrl: "https://www.reddit.com/"
    )
}
