//
//  StreamFallbackTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

private func cachedResult(videoId: String) -> PlaybackResult {
    PlaybackResult(
        streamUrl: "https://example/s",
        itag: 251,
        mimeType: "audio/webm",
        bitrate: 160000,
        audioQuality: "AUDIO_QUALITY_HIGH",
        videoId: videoId,
        title: "t",
        author: "a",
        duration: 213,
        expiresInSeconds: 3600,
        clientName: "WEB",
        musicVideoType: nil,
        hasVideoContent: false,
        muxedStreamUrl: nil,
        loudnessDb: nil
    )
}

@Suite("StreamFallback")
struct StreamFallbackTests {
    @Test("Policy and request presets")
    func presets() {
        #expect(FallbackPolicy.playback.useCache == true)
        #expect(FallbackPolicy.playback.preferAAC == false)
        #expect(FallbackPolicy.download.useCache == false)
        #expect(FallbackPolicy.download.preferAAC == true)

        let playback = StreamResolveRequest.playback(videoId: "v")
        #expect(playback.chain.count == ClientFallbackChain.preferred.count)
        #expect(playback.policy.useCache == true)

        let download = StreamResolveRequest.download(videoId: "v")
        #expect(download.options.forDownload == true)
        #expect(download.chain.count == ClientFallbackChain.forDownload.count)
        #expect(download.policy.preferAAC == true)
    }

    @Test("mpv EDL escapes URLs by length")
    func edl() {
        let edl = StreamFallback.combineVideoAndAudio(
            videoURL: "https://example/v?a=1;b=2",
            audioURL: "https://example/a",
            duration: 213
        )
        #expect(edl.hasPrefix("edl://"))
        #expect(edl.contains("https://example/v?a=1;b=2"))
        #expect(edl.contains("https://example/a"))
        #expect(edl.contains(",length=213"))
    }

    @Test("resolveFormatURL passes direct URLs, throws without cipher providers")
    func formatURL() async {
        let direct = try? JSONDecoder().decode(
            Format.self,
            from: Data(#"{"itag":18,"url":"https://example/m"}"#.utf8)
        )
        #expect(await (try? StreamFallback.resolveFormatURL(direct!)) == "https://example/m")

        let ciphered = try? JSONDecoder().decode(
            Format.self,
            from: Data(#"{"itag":22,"signatureCipher":"url=https%3A%2F%2Fexample%2F&s=abc&sp=sig"}"#.utf8)
        )
        do {
            _ = try await StreamFallback.resolveFormatURL(ciphered!)
            Issue.record("expected noStreamUrl")
        } catch let error as StreamError {
            #expect(error.errorDescription == StreamError.noStreamUrl.errorDescription)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("Cache hit returns without network")
    func cacheHit() async throws {
        let cache = StreamCache()
        await cache.set(videoId: "cached-v", result: cachedResult(videoId: "cached-v"))
        let client = InnerTubeClient(config: .youtube)
        let request = StreamResolveRequest(videoId: "cached-v", chain: [], policy: .playback)
        let result = try await StreamFallback.resolveFirstValid(request, using: client, cache: cache)
        #expect(result.itag == 251)
    }

    @Test("Expired-cache fallback works with empty chain")
    func expiredFallback() async throws {
        let cache = StreamCache()
        await cache.set(videoId: "expired-v", result: cachedResult(videoId: "expired-v"))
        let client = InnerTubeClient(config: .youtube)
        var policy = FallbackPolicy.playback
        policy.useCache = false
        let request = StreamResolveRequest(videoId: "expired-v", chain: [], policy: policy)
        let result = try await StreamFallback.resolveFirstValid(request, using: client, cache: cache)
        #expect(result.videoId == "expired-v")
    }

    @Test("Empty chain with no cache throws allClientsFailed")
    func emptyChain() async {
        let client = InnerTubeClient(config: .youtube)
        let request = StreamResolveRequest(
            videoId: "missing-v",
            chain: [],
            policy: FallbackPolicy(
                useCache: false,
                storeInCache: false,
                validateStreams: false,
                expiredCacheFallback: false,
                preferAAC: false
            )
        )
        do {
            _ = try await StreamFallback.resolveFirstValid(request, using: client, cache: StreamCache())
            Issue.record("expected throw")
        } catch let error as StreamError {
            #expect(error.errorDescription == StreamError.allClientsFailed.errorDescription)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
