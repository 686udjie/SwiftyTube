//
//  InnerTubeLiveTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

// Live smoke tests against the real InnerTube API (guest, keyless).
// These prove the transport actually works end to end.

import Testing

@testable import SwiftyTube

@Suite("InnerTube live")
struct InnerTubeLiveTests {
    @Test("YouTube search returns contents")
    func youtubeSearch() async throws {
        let client = InnerTubeClient(config: .youtube)
        let json = try await client.search(query: "lofi hip hop")
        #expect(json["contents"] != nil)
    }

    @Test("Browse captures visitorData into auth")
    func browseCapturesVisitorData() async throws {
        let client = InnerTubeClient(config: .youtube)
        let json = try await client.browse(browseId: "FEwhat_to_watch")
        #expect(json["contents"] != nil)
        let auth = await client.currentAuth()
        #expect(auth.visitorData != nil)
    }

    @Test("YouTube Music search returns contents")
    func musicSearch() async throws {
        let client = InnerTubeClient(config: .music)
        let json = try await client.search(query: "lofi")
        #expect(json["contents"] != nil)
    }

    @Test("Country charts resolve a regional trending playlist")
    func regionalTrending() async throws {
        let client = InnerTubeClient(config: .music)
        let playlistId = try await RegionalCharts.trendingPlaylistId(country: "JP", using: client)
        #expect(playlistId.hasPrefix("VL"))
    }
}
