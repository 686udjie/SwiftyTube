//
//  CoreCoverageTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

@Suite("Core coverage")
struct CoreCoverageTests {
    @Test("All client presets carry their identities")
    func presets() {
        #expect(YouTubeClient.visionOS.clientName == "VISIONOS")
        #expect(YouTubeClient.visionOS.skipPlayerResponseValidation == true)
        #expect(YouTubeClient.androidVr1_65_10.clientName == "ANDROID_VR")
        #expect(YouTubeClient.androidVr1_65_10.useMusicPlayerEndpoint == true)
        #expect(YouTubeClient.androidVr1_43_32.clientVersion == "1.43.32")
        #expect(YouTubeClient.androidVr1_61_48.clientVersion == "1.61.48")
        #expect(YouTubeClient.tvHtml5.clientName == "TVHTML5")
        #expect(YouTubeClient.tvHtml5.loginSupported == true)
        #expect(YouTubeClient.tvHtml5SimplyEmbedded.isEmbedded == true)
        #expect(YouTubeClient.tvHtml5SimplyEmbedded.embedUrl == "https://www.reddit.com/")
        #expect(YouTubeClient.mobile.clientName == "ANDROID")
        #expect(YouTubeClient.web.useSignatureTimestamp == true)
        #expect(YouTubeClient.web.useWebPoTokens == true)
        #expect(YouTubeClient.webRemix.useSignatureTimestamp == true)
        #expect(YouTubeClient.iOS.includeUserAgentInContext == true)
    }

    @Test("Client survives a Codable round trip")
    func clientCodable() throws {
        let data = try JSONEncoder().encode(YouTubeClient.webRemix)
        let decoded = try JSONDecoder().decode(YouTubeClient.self, from: data)
        #expect(decoded == YouTubeClient.webRemix)
    }

    @Test("Config stores custom values")
    func config() {
        let config = SwiftyTubeConfig(
            service: .youtube,
            defaultClient: .iOS,
            defaultLocale: YouTubeLocale(gl: "DE", hl: "de"),
            timeoutSeconds: 5,
            acceptLanguage: "de-DE,de;q=0.9"
        )
        #expect(config.defaultClient.clientName == "IOS")
        #expect(config.defaultLocale.gl == "DE")
        #expect(config.timeoutSeconds == 5)
        #expect(config.acceptLanguage == "de-DE,de;q=0.9")
    }

    @Test("Value types store their fields")
    func values() {
        let locale = YouTubeLocale(gl: "JP", hl: "ja")
        #expect(locale.gl == "JP")
        let auth = AuthState(cookies: ["A": "b"], sapisid: "s", visitorData: "v", dataSyncId: "d")
        #expect(auth.cookies == ["A": "b"])
        #expect(auth.dataSyncId == "d")
        let account = AccountInfo(name: "n", email: "e", channelHandle: "h", thumbnailUrl: "u")
        #expect(account.name == "n")
        #expect(account.thumbnailUrl == "u")
        #expect(AccountInfo(name: "Guest").email == nil)
    }

    @Test("Log handler receives every level")
    func logHandler() {
        var received: [(String, SwiftyTubeLog.Level)] = []
        SwiftyTubeLog.handler = { received.append(($0, $1)) }
        SwiftyTubeLog.debug("d")
        SwiftyTubeLog.info("i")
        SwiftyTubeLog.notice("n")
        SwiftyTubeLog.error("e")
        SwiftyTubeLog.handler = nil
        #expect(received.map { $0.1 } == [.debug, .info, .notice, .error])
    }

    @Test("Error descriptions are non-empty")
    func errors() {
        let innerTube: [InnerTubeError] = [
            .invalidResponse,
            .httpError(statusCode: 500, data: Data()),
            .decodingFailed
        ]
        for error in innerTube {
            #expect((error.errorDescription ?? "").isEmpty == false)
        }
        #expect(RetryError.exhausted is Error)
        let stream: [StreamError] = [
            .unplayable(reason: "r"),
            .noStreams,
            .noSuitableFormat,
            .noStreamUrl,
            .validationFailed("c"),
            .allClientsFailed
        ]
        for error in stream {
            #expect((error.errorDescription ?? "").isEmpty == false)
        }
        let botGuard: [BotGuardError] = [.createFailed, .generateITFailed, .invalidResponse, .descrambleFailed]
        for error in botGuard {
            #expect((error.errorDescription ?? "").isEmpty == false)
        }
        let cipher: [CipherError] = [
            .hashNotFound,
            .invalidResponse("x"),
            .cacheUnavailable,
            .signatureTimestampNotFound,
            .functionNotFound("f"),
            .jsExecutionFailed("j"),
            .configNotAvailable,
            .deobfuscationFailed("d"),
            .nTransformFailed("n")
        ]
        for error in cipher {
            #expect((error.errorDescription ?? "").isEmpty == false)
        }
    }

    @Test("PlayerConfig expressions")
    func playerConfig() {
        #expect(PlayerConfig().nJsExpression == nil)
        let config = PlayerConfig(sig: "Ab(1,2,INPUT)", nClass: "W_", sts: 1)
        #expect(config.sigFunction.body == "Ab(1,2,INPUT)")
        #expect(config.nFunction.varName == "W_")
        #expect(config.nJsExpression?.contains("W_") == true)
        #expect(ExtractedFunction(body: "b").body == "b")
    }

    @Test("Request option defaults")
    func options() {
        #expect(PlayerRequestOptions.default.signatureTimestamp == nil)
        #expect(PlayerRequestOptions.default.poToken == nil)
        #expect(StreamResolveOptions.default.forDownload == false)
        #expect(StreamResolveOptions.default.audioQuality == .auto)
        #expect(StreamResolveOptions.default.downloadQuality == .high)
        #expect(StreamResolveProviders.none.signatureTimestamp == nil)
        #expect(StreamResolveProviders.none.poTokenProvider == nil)
        #expect(FallbackClient(client: .web, skipValidation: false) == FallbackClient(client: .web, skipValidation: false))
    }

    @Test("Quality enums")
    func quality() {
        #expect(AudioQuality.allCases.count == 4)
        #expect(DownloadQuality.allCases.count == 3)
        #expect(AudioQuality.high.rawValue == "high")
        #expect(DownloadQuality.standard.rawValue == "standard")
    }

    @Test("PoToken value types")
    func poTokenValues() {
        let result = PoTokenResult(playerRequestPoToken: "p", streamingDataPoToken: "s")
        #expect(result.playerRequestPoToken == "p")
        let challenge = BotGuardChallenge(
            program: "pg",
            messageId: "m",
            interpreterHash: "h",
            globalName: "g",
            interpreterJavascript: nil
        )
        #expect(challenge.program == "pg")
        #expect(challenge.interpreterJavascript == nil)
    }
}
