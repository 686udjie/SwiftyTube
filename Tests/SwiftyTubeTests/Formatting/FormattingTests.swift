//
//  FormattingTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 10/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

@Suite("Formatting")
struct FormattingTests {
    @Test("Playback time rolls hours over at 60 minutes")
    func playbackTime() {
        #expect(DurationFormat.playbackTime(0) == "0:00")
        #expect(DurationFormat.playbackTime(16) == "0:16")
        #expect(DurationFormat.playbackTime(205) == "3:25")
        #expect(DurationFormat.playbackTime(3599) == "59:59")
        #expect(DurationFormat.playbackTime(3600) == "1:00:00")
        #expect(DurationFormat.playbackTime(5601) == "1:33:21")
    }

    @Test("Clock parsing is anchored so counts never read as durations")
    func parseClock() {
        #expect(DurationFormat.parseClock("3:21") == 201)
        #expect(DurationFormat.parseClock("1:33:21") == 5601)
        #expect(DurationFormat.parseClock("1,234") == nil)
        #expect(DurationFormat.parseClock("2024") == nil)
        #expect(DurationFormat.parseClock("14K views") == nil)
        #expect(DurationFormat.parseClock("") == nil)
    }

    @Test("Renderer duration tries every known shape in order")
    func rendererDuration() {
        #expect(DurationFormat.parseRendererDuration([:]) == 0)
        #expect(DurationFormat.parseRendererDuration(["lengthSeconds": "200"]) == 200)
        #expect(DurationFormat.parseRendererDuration(["lengthSeconds": 200]) == 200)
        #expect(
            DurationFormat.parseRendererDuration(["lengthText": ["runs": [["text": "3:25"]]]]) == 205
        )
        #expect(
            DurationFormat.parseRendererDuration([
                "badges": [["musicInlineBadgeRenderer": ["text": ["runs": [["text": "4:01"]]]]]]
            ]) == 241
        )
        #expect(
            DurationFormat.parseRendererDuration([
                "subtitle": ["runs": [["text": "Song"], ["text": " • "], ["text": "2:30"]]]
            ]) == 150
        )
        #expect(
            DurationFormat.parseRendererDuration([
                "subtitle": ["runs": [
                    ["text": "Video"], ["text": " • "], ["text": "Aria"],
                    ["text": " • "], ["text": "1:33:21"], ["text": " • "], ["text": "42K views"]
                ]]
            ]) == 5601
        )
        #expect(
            DurationFormat.parseRendererDuration([
                "flexColumns": [[
                    "musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "x"]]]]
                ], [
                    "musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [
                        ["text": "Artist"], ["text": " • "], ["text": "5:00"]
                    ]]]
                ]]
            ]) == 300
        )
        #expect(
            DurationFormat.parseRendererDuration([
                "fixedColumns": [[
                    "musicResponsiveListItemFixedColumnRenderer": ["text": ["runs": [["text": "1:00"]]]]
                ]]
            ]) == 60
        )
    }

    @Test("Community playlists skip radio, mixes and albums")
    func communityPlaylists() {
        func row(title: String, browseId: String) -> [String: Any] {
            ["musicResponsiveListItemRenderer": [
                "flexColumns": [
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": title]]]]],
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Playlist"]]]]]
                ],
                "navigationEndpoint": ["browseEndpoint": ["browseId": browseId]]
            ]]
        }
        let json: [String: Any] = ["contents": ["singleColumnBrowseResultsRenderer": ["tabs": [[
            "tabRenderer": ["content": ["sectionListRenderer": ["contents": [[
                "musicShelfRenderer": ["contents": [
                    row(title: "Gym", browseId: "VLPL1"),
                    row(title: "Radio", browseId: "RDAMVMx"),
                    row(title: "Mix", browseId: "OLAK5uy_x"),
                    row(title: "Album", browseId: "MPREb_x")
                ]]
            ]]]]]
        ]]]]]
        let playlists = LibraryBrowseParser.extractCommunityPlaylists(from: json)
        #expect(playlists.map(\.browseId) == ["VLPL1"])
        #expect(LibraryBrowseParser.normalizePlaylistId("VLPL1") == "PL1")
        #expect(LibraryBrowseParser.normalizePlaylistId("PL1") == "PL1")
    }
}
