//
//  StreamingTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

private func decodeFormat(_ json: String) -> Format {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode(Format.self, from: Data(json.utf8))
}

@Suite("Streaming")
struct StreamingTests {
    @Test("Format codec extraction")
    func codec() {
        let opus = decodeFormat(
            #"{"itag":249,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":50000,"audioQuality":"AUDIO_QUALITY_LOW","audioChannels":2}"#
        )
        #expect(opus.codec == "opus")
        #expect(opus.isAudioOnly == true)
        let plain = decodeFormat(#"{"itag":18,"mimeType":"video/mp4","width":640,"height":360}"#)
        #expect(plain.codec == "video/mp4")
        #expect(plain.isAudioOnly == false)
    }

    @Test("bestAudioFormat prefers quality then opus")
    func bestAudio() {
        let low = decodeFormat(
            #"{"itag":249,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":50000,"audioQuality":"AUDIO_QUALITY_LOW","audioChannels":2}"#
        )
        let high = decodeFormat(
            #"{"itag":251,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":160000,"audioQuality":"AUDIO_QUALITY_HIGH","audioChannels":2,"url":"https://example/x"}"#
        )
        #expect(FormatSelector.bestAudioFormat(from: [low, high])?.itag == 251)
        #expect(FormatSelector.bestAudioFormat(from: [low, high], preference: .low)?.itag == 249)
        #expect(FormatSelector.bestAudioFormat(from: []) == nil)
    }

    @Test("bestVideoFormat needs muxed H264 with URL")
    func bestVideo() {
        let dash = decodeFormat(
            #"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","width":1920,"height":1080,"url":"https://example/v"}"#
        )
        let muxed = decodeFormat(
            #"{"itag":18,"mimeType":"video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"","width":640,"height":360,"audioChannels":2,"url":"https://example/m"}"#
        )
        #expect(FormatSelector.bestVideoFormat(from: [dash, muxed])?.itag == 18)
        #expect(FormatSelector.bestVideoFormat(from: [dash]) == nil)
    }

    @Test("Fallback chain covers direct-URL and web clients")
    func fallbackChain() {
        #expect(ClientFallbackChain.preferred.count == 9)
        #expect(ClientFallbackChain.forDownload.count == 9)
        #expect(ClientFallbackChain.preferred.first?.client.clientName == "VISIONOS")
        #expect(ClientFallbackChain.preferred.last?.client.clientName == "WEB_REMIX")
    }

    @Test("PlayerResponse decodes and reports playability")
    func playerResponse() throws {
        let json = """
        {"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"abc","lengthSeconds":"213"}}
        """
        let response = try JSONDecoder().decode(PlayerResponse.self, from: Data(json.utf8))
        #expect(response.isPlayable == true)
        #expect(response.videoDetails?.lengthSeconds == "213")
    }

    @Test("StreamCache round-trips until expiry")
    func streamCache() async {
        let cache = StreamCache()
        let result = PlaybackResult(
            streamUrl: "https://example/s",
            itag: 251,
            mimeType: "audio/webm",
            bitrate: 160000,
            audioQuality: "AUDIO_QUALITY_HIGH",
            videoId: "abc",
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
        await cache.set(videoId: "abc", result: result)
        #expect(await cache.get(videoId: "abc")?.itag == 251)
        await cache.remove(videoId: "abc")
        #expect(await cache.get(videoId: "abc") == nil)
    }

    @Test("Live duration fetch via iOS client")
    func liveDuration() async throws {
        let client = InnerTubeClient(config: .youtube)
        let duration = try await client.fetchDuration(videoId: "dQw4w9WgXcQ")
        #expect(duration > 0)
    }

    @Test("Live resolve reports format info to handler")
    func liveResolveHandler() async throws {
        let client = InnerTubeClient(config: .youtube)
        let seen = LockedBox<ResolvedFormatInfo>()
        var providers = StreamResolveProviders.none
        providers.resolvedFormatHandler = { info in
            await seen.set(info)
        }
        do {
            let result = try await StreamResolver.resolve(
                videoId: "dQw4w9WgXcQ",
                client: .iOS,
                using: client,
                providers: providers
            )
            #expect(result.streamUrl.hasPrefix("http"))
            let info = await seen.value
            #expect(info?.videoId == "dQw4w9WgXcQ")
            #expect((info?.itag ?? 0) > 0)
        } catch let error as StreamError {
            // API-side unavailability (rotations, cipher-only responses) -
            // the wiring is what matters, not today's stream inventory.
            switch error {
            case .noStreamUrl, .unplayable, .noStreams, .noSuitableFormat:
                return
            default:
                throw error
            }
        }
    }
}

private actor LockedBox<T> {
    private(set) var value: T?
    func set(_ value: T) {
        self.value = value
    }
}
