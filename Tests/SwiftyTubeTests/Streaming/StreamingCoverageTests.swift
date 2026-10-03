//
//  StreamingCoverageTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

private func format(_ json: String) -> Format {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode(Format.self, from: Data(json.utf8))
}

@Suite("Streaming coverage")
struct StreamingCoverageTests {
    @Test("Download selection honors quality tiers")
    func downloadTiers() {
        let aac128 = format(
            #"{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"audioChannels":2,"url":"https://example/a"}"#
        )
        let aac256 = format(
            #"{"itag":141,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":256000,"audioChannels":2,"url":"https://example/b"}"#
        )
        let opus160 = format(
            #"{"itag":251,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":160000,"audioChannels":2,"url":"https://example/c"}"#
        )
        let all = [aac128, aac256, opus160]

        // High: AAC pool wins, best bitrate wins.
        #expect(FormatSelector.bestDownloadFormat(from: all)?.itag == 141)
        // Standard: capped near 96k, smallest wins.
        #expect(FormatSelector.bestDownloadFormat(from: all, downloadQuality: .standard)?.itag == 140)
        #expect(FormatSelector.bestDownloadFormat(from: []) == nil)
    }

    @Test("Audio preference tiers filter before scoring")
    func audioTiers() {
        let medium = format(
            #"{"itag":250,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":70000,"audioQuality":"AUDIO_QUALITY_MEDIUM","audioChannels":2}"#
        )
        let high = format(
            #"{"itag":251,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":160000,"audioQuality":"AUDIO_QUALITY_HIGH","audioChannels":2}"#
        )
        #expect(FormatSelector.bestAudioFormat(from: [medium, high], preference: .medium)?.itag == 250)
        #expect(FormatSelector.bestAudioFormat(from: [medium, high], preference: .high)?.itag == 251)
    }

    @Test("Audio-bearing falls back to combined, then nil")
    func audioBearing() {
        let combined = format(
            #"{"itag":18,"mimeType":"video/mp4","width":640,"height":360,"audioChannels":2}"#
        )
        #expect(FormatSelector.audioBearingFormats([combined])?.count == 1)
        let videoOnly = format(#"{"itag":137,"mimeType":"video/mp4","width":1920,"height":1080}"#)
        #expect(FormatSelector.audioBearingFormats([videoOnly]) == nil)
        #expect(FormatSelector.audioBearingFormats([]) == nil)
    }

    @Test("H264 pool falls back to full pool")
    func h264Pool() {
        let vp9 = format(#"{"itag":248,"mimeType":"video/webm; codecs=\"vp9\"","width":1920,"height":1080}"#)
        #expect(FormatSelector.h264PreferredPool([vp9], kind: "x").count == 1)
    }

    @Test("Video-only selection caps at 720p")
    func videoOnlyCap() {
        let p1080 = format(
            #"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","width":1920,"height":1080,"url":"https://example/h"}"#
        )
        let p720 = format(
            #"{"itag":136,"mimeType":"video/mp4; codecs=\"avc1.4d401f\"","width":1280,"height":720,"url":"https://example/m"}"#
        )
        #expect(FormatSelector.bestVideoOnlyFormat(from: [p1080, p720])?.itag == 136)
        #expect(FormatSelector.bestVideoFormat(from: []) == nil)
        #expect(FormatSelector.bestVideoOnlyFormat(from: []) == nil)
    }

    @Test("PlaybackResult survives a Codable round trip")
    func playbackResultCodable() throws {
        let result = PlaybackResult(
            streamUrl: "u",
            itag: 1,
            mimeType: "m",
            bitrate: 2,
            audioQuality: "q",
            videoId: "v",
            title: nil,
            author: nil,
            duration: nil,
            expiresInSeconds: 3,
            clientName: "c",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
        let decoded = try JSONDecoder().decode(PlaybackResult.self, from: try JSONEncoder().encode(result))
        #expect(decoded == result)
    }

    @Test("StreamCache expiry and clear")
    func streamCache() async {
        let cache = StreamCache()
        let result = PlaybackResult(
            streamUrl: "u",
            itag: 1,
            mimeType: "m",
            bitrate: 2,
            audioQuality: "q",
            videoId: "v",
            title: nil,
            author: nil,
            duration: nil,
            expiresInSeconds: 3600,
            clientName: "c",
            musicVideoType: nil,
            hasVideoContent: false,
            muxedStreamUrl: nil,
            loudnessDb: nil
        )
        #expect(await cache.get(videoId: "v") == nil)
        await cache.set(videoId: "v", result: result)
        #expect(await cache.getExpired(videoId: "v")?.itag == 1)
        await cache.clear()
        #expect(await cache.getExpired(videoId: "v") == nil)
    }

    @Test("DurationCache pending lifecycle")
    func durationPending() {
        #expect(DurationCache.get("nope") == nil)
        DurationCache.markPending("p1")
        #expect(DurationCache.isPending("p1") == true)
        DurationCache.clearPending("p1")
        #expect(DurationCache.isPending("p1") == false)
    }

    @Test("EDL without duration omits length")
    func edlNoDuration() {
        let edl = StreamFallback.combineVideoAndAudio(videoURL: "v", audioURL: "a", duration: nil)
        #expect(edl.contains("length") == false)
        #expect(edl.hasPrefix("edl://"))
    }

    @Test("VideoStream cases carry URLs")
    func videoStream() {
        let muxed = VideoStream.muxed("u")
        if case .muxed(let url) = muxed {
            #expect(url == "u")
        } else {
            Issue.record("wrong case")
        }
        let split = VideoStream.split(video: "v", audio: "a", duration: 1)
        if case .split(let video, let audio, let duration) = split {
            #expect(video == "v")
            #expect(audio == "a")
            #expect(duration == 1)
        } else {
            Issue.record("wrong case")
        }
    }

    @Test("Request defaults")
    func requestDefaults() {
        let request = StreamResolveRequest(videoId: "v")
        #expect(request.chain.count == ClientFallbackChain.preferred.count)
        #expect(request.policy.useCache == true)
        #expect(request.options.audioQuality == .auto)
    }
}
