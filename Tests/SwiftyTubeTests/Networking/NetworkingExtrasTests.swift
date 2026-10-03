//
//  NetworkingExtrasTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Testing

@testable import SwiftyTube

@Suite("Networking extras")
struct NetworkingExtrasTests {
    @Test("CookieParser splits pairs and skips junk")
    func cookieParser() {
        let parsed = CookieParser.parse("SID=abc; HSID=def;  empty; SAPISID=xyz")
        #expect(parsed == ["SID": "abc", "HSID": "def", "SAPISID": "xyz"])
        #expect(CookieParser.parse("").isEmpty)
    }

    @Test("InnerTubeJSON runs and thumbnails")
    func jsonHelpers() {
        #expect(InnerTubeJSON.runsText(["runs": [["text": "a"], ["text": "b"]]]) == "ab")
        #expect(InnerTubeJSON.runsText(["simpleText": "hi"]) == "hi")
        #expect(InnerTubeJSON.runsText(nil) == nil)
        #expect(InnerTubeJSON.runsTexts(["runs": [["text": "a"], ["text": " • "], ["text": " "]]]) == ["a"])
        #expect(InnerTubeJSON.lastThumbnailURL([["url": "small"], ["url": "big"]]) == "big")
        #expect(InnerTubeJSON.nestedThumbnailURL(["thumbnail": ["thumbnails": [["url": "u"]]]]) == "u")
    }

    @Test("InnerTubeDecode paths and coercions")
    func decodeHelpers() {
        let dict: [String: Any] = ["a": ["b": ["c": "found"]], "n": "42"]
        #expect(InnerTubeDecode.string(at: ["a", "b", "c"], in: dict) == "found")
        #expect(InnerTubeDecode.string(at: ["a", "missing"], in: dict) == nil)
        #expect(InnerTubeDecode.intFromStringOrInt("42") == 42)
        #expect(InnerTubeDecode.intFromStringOrInt(7) == 7)
        #expect(InnerTubeDecode.intFromStringOrInt(nil) == nil)
    }

    @Test("RetryPolicy retries then succeeds")
    func retrySucceeds() async throws {
        let policy = RetryPolicy(
            maxAttempts: 3,
            baseDelay: .milliseconds(1),
            factor: 2,
            maxDelay: .milliseconds(5),
            jitter: .milliseconds(0)
        )
        var calls = 0
        let result = try await policy.run(
            { calls += 1; return try Self.flaky(calls: calls) },
            isRetryable: { _ in true }
        )
        #expect(result == "ok")
        #expect(calls == 3)
    }

    @Test("RetryPolicy gives up on non-retryable errors")
    func retryGivesUp() async {
        let policy = RetryPolicy(
            maxAttempts: 3,
            baseDelay: .milliseconds(1),
            factor: 2,
            maxDelay: .milliseconds(5),
            jitter: .milliseconds(0)
        )
        var calls = 0
        do {
            _ = try await policy.run(
                { calls += 1; throw InnerTubeError.decodingFailed as Error },
                isRetryable: { _ in false }
            )
            Issue.record("expected throw")
        } catch {
            #expect(calls == 1)
        }
    }

    @Test("DurationCache stores and tracks pending")
    func durationCache() {
        DurationCache.markPending("vid1")
        #expect(DurationCache.isPending("vid1") == true)
        #expect(DurationCache.get("vid1") == nil)
        DurationCache.set("vid1", 123)
        #expect(DurationCache.get("vid1") == 123)
        #expect(DurationCache.isPending("vid1") == false)
        DurationCache.clearPending("vid1")
    }

    @Test("updateLocale changes defaults")
    func updateLocale() async {
        let client = InnerTubeClient(config: .youtube)
        await client.updateLocale(YouTubeLocale(gl: "DE", hl: "de"))
        let config = await client.config
        #expect(config.defaultLocale.gl == "DE")
        #expect(config.acceptLanguage == "en-DE,en;q=0.9")
    }

    @Test("loadState pulls from provider")
    func loadState() async {        struct Stub: AuthStateProvider {
            func cookies() async -> [String: String] { ["SID": "x"] }
            func sapisid() async -> String? { "s" }
            func visitorData() async -> String? { "v" }
            func dataSyncId() async -> String? { nil }
        }
        let client = InnerTubeClient(config: .youtube)
        await client.loadState(from: Stub())
        let auth = await client.currentAuth()
        #expect(auth.cookies == ["SID": "x"])
        #expect(auth.sapisid == "s")
        #expect(auth.visitorData == "v")
    }

    private static func flaky(calls: Int) throws -> String {
        if calls < 3 { throw HttpError.notHTTPResponse }
        return "ok"
    }
}
