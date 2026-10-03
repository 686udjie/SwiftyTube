//
//  NetworkingCoverageTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

@Suite("Networking coverage")
struct NetworkingCoverageTests {
    @Test("Playback tracking request carries cpn and playlist")
    func trackingRequest() {
        let request = RequestBuilder.buildPlaybackTrackingRequest(
            config: .youtube,
            trackingUrl: "https://www.youtube.com/api/stats/watchtime",
            client: .web,
            auth: AuthState(cookies: ["SID": "x"], sapisid: "s", visitorData: "v"),
            playlistId: "PL123"
        )
        #expect(request?.httpMethod == "GET")
        let url = request?.url?.absoluteString ?? ""
        #expect(url.contains("c=WEB"))
        #expect(url.contains("ver=2"))
        #expect(url.contains("list=PL123"))
        #expect(url.contains("cpn="))
        #expect(request?.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == "v")
        #expect(request?.value(forHTTPHeaderField: "Cookie") == "SID=x")
        #expect(request?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH ") == true)
    }

    @Test("Tracking cpn is 16 URL-safe chars")
    func trackingCpn() {
        let request = RequestBuilder.buildPlaybackTrackingRequest(
            config: .music,
            trackingUrl: "https://music.youtube.com/api/stats/watchtime",
            client: .webRemix,
            auth: .guest
        )
        let query = URLComponents(url: request!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let cpn = query.first(where: { $0.name == "cpn" })?.value ?? ""
        #expect(cpn.count == 16)
        #expect(request?.value(forHTTPHeaderField: "X-Origin") == "https://music.youtube.com")
    }

    @Test("Stream validation fails closed on bad URLs")
    func validateBadURL() async {
        #expect(await StreamResolver.validateStream(url: "not a url") == false)
    }

    @Test("Retry delays grow and cap")
    func retryDelays() {
        let policy = RetryPolicy(
            maxAttempts: 3,
            baseDelay: .milliseconds(500),
            factor: 2,
            maxDelay: .seconds(30),
            jitter: .milliseconds(200)
        )
        #expect(policy.delay(for: 0) >= .milliseconds(500))
        #expect(policy.delay(for: 0) <= .milliseconds(700))
        // 0.5s * 2^10 overflows the 30s cap.
        #expect(policy.delay(for: 10) >= .seconds(30))
        #expect(policy.delay(for: 10) <= .milliseconds(30200))
    }

    @Test("Zero attempts throws exhausted")
    func retryExhausted() async {
        let policy = RetryPolicy(
            maxAttempts: 0,
            baseDelay: .milliseconds(1),
            factor: 2,
            maxDelay: .milliseconds(1),
            jitter: .milliseconds(0)
        )
        do {
            _ = try await policy.run({ 1 }, isRetryable: { _ in true })
            Issue.record("expected throw")
        } catch let error as RetryError {
            #expect(error == .exhausted)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("Decode path helpers and thumbnail envelopes")
    func decodeHelpers() {
        let dict: [String: Any] = ["a": ["b": ["c": 1]], "arr": [["x": 1]]]
        let nested = InnerTubeDecode.dict(at: ["a", "b"], in: dict)
        #expect(nested?["c"] as? Int == 1)
        #expect(InnerTubeDecode.array(at: ["arr"], in: dict)?.count == 1)
        #expect(InnerTubeDecode.value(at: ["a", "missing", "deep"], in: dict) == nil)

        let music: [String: Any] = [
            "thumbnail": ["musicThumbnailRenderer": ["thumbnail": ["thumbnails": [["url": "m"]]]]]
        ]
        #expect(InnerTubeDecode.thumbnailURLTolerant(music) == "m")
        #expect(InnerTubeDecode.thumbnailURLTolerant(["thumbnail": ["thumbnails": [["url": "t"]]]]) == "t")
        #expect(InnerTubeDecode.thumbnailURLTolerant(["thumbnails": [["url": "b"]]]) == "b")
        #expect(InnerTubeDecode.thumbnailURLTolerant(
            ["croppedSquareThumbnail": ["thumbnails": [["url": "c"]]]]
        ) == "c")
        #expect(InnerTubeDecode.thumbnailURLTolerant(nil) == nil)
        #expect(InnerTubeDecode.thumbnailURLTolerant([:]) == nil)
        #expect(InnerTubeDecode.intFromStringOrInt(NSNumber(value: 1.9)) == 1)
        #expect(InnerTubeDecode.intFromStringOrInt(1.5) == 1)
    }

    @Test("JSON helpers tolerate unknown shapes")
    func jsonHelpers() {
        #expect(InnerTubeJSON.nestedThumbnailURL(nil) == nil)
        #expect(InnerTubeJSON.musicThumbnailURL(["weird": 1]) == nil)
        #expect(InnerTubeJSON.runsTexts(nil).isEmpty)
        #expect(InnerTubeJSON.runsTexts([:]).isEmpty)
        #expect(InnerTubeJSON.rawRuns(nil).isEmpty)
        #expect(InnerTubeJSON.lastThumbnailURL(nil) == nil)
        #expect(InnerTubeJSON.runsText(["runs": [["text": ""]]]) == nil)
    }

    @Test("Cookie edge cases")
    func cookies() {
        #expect(CookieParser.parse("a==b") == ["a": "=b"])
        #expect(CookieParser.parse("novalue; B=2") == ["B": "2"])
    }

    @Test("Query encoding escapes reserved chars")
    func queryEncoding() {
        let encoded = StreamResolver.encodeQueryValue("a+b/c=d&e")
        #expect(encoded.contains("+") == false)
        #expect(encoded.contains("/") == false)
        #expect(encoded.removingPercentEncoding == "a+b/c=d&e")
    }
}
