//
//  ArtistCreditsTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 15/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

// Fixtures use the exact shapes InnerTube returns (see issue #1: a
// label-and-artist collab, "Thriller Records & Dark Divine").

private func run(
    _ text: String,
    browseId: String? = nil,
    pageType: String? = nil,
    // Shelf rows nest the music config inside browseEndpoint; watch panels
    // hoist it to navigationEndpoint level. Cover both.
    panelShaped: Bool = false
) -> [String: Any] {
    guard let browseId else { return ["text": text] }
    var browse: [String: Any] = ["browseId": browseId]
    var nav: [String: Any] = [:]
    if let pageType {
        let supported: [String: Any] = ["browseEndpointContextSupportedConfigs": [
            "browseEndpointContextMusicConfig": ["pageType": pageType]
        ]]
        if panelShaped {
            nav = supported
        } else {
            browse.merge(supported) { current, _ in current }
        }
    }
    nav["browseEndpoint"] = browse
    return ["text": text, "navigationEndpoint": nav]
}

private let artistPage = "MUSIC_PAGE_TYPE_ARTIST"
private let topicPage = "MUSIC_PAGE_TYPE_USER_CHANNEL"

@Suite("ArtistCredits")
struct ArtistCreditsTests {
    // The issue shape: label + artist joined by "&" in a shelf subtitle.
    @Test("keeps both artists around a conjunction")
    func issueShelfShape() {
        let runs = [
            run("Song"), run(" • "),
            run("Thriller Records", browseId: "UCaR2hMhiQHeiBtLDCcdwwUA", pageType: artistPage),
            run(" & "),
            run("Dark Divine", browseId: "UCvgu5VJWazm1jDevS18qDFg", pageType: artistPage)
        ]
        #expect(ArtistCredits.parse(runs: runs) == [
            ArtistCredit(name: "Thriller Records", browseId: "UCaR2hMhiQHeiBtLDCcdwwUA"),
            ArtistCredit(name: "Dark Divine", browseId: "UCvgu5VJWazm1jDevS18qDFg")
        ])
    }

    @Test("single panel byline stays single")
    func singlePanelByline() {
        let runs = [run("Dark Divine", browseId: "UCvgu5VJWazm1jDevS18qDFg", pageType: artistPage, panelShaped: true)]
        #expect(ArtistCredits.parse(runs: runs) == [
            ArtistCredit(name: "Dark Divine", browseId: "UCvgu5VJWazm1jDevS18qDFg")
        ])
    }

    @Test("drops labels, separators, years and counts")
    func dropsJunk() {
        let runs = [run("Album"), run(" • "), run("&"), run("2024"), run("1.2M plays"), run(" • ")]
        #expect(ArtistCredits.parse(runs: runs).isEmpty)
    }

    @Test("skips album and playlist links")
    func skipsReleaseLinks() {
        let runs = [
            run("Some Album", browseId: "MPREb_abc123"),
            run("A Playlist", browseId: "VLxyz", pageType: "MUSIC_PAGE_TYPE_PLAYLIST")
        ]
        #expect(ArtistCredits.parse(runs: runs).isEmpty)
    }

    @Test("topic channels keep their id for direct navigation")
    func topicChannel() {
        // A channel page for the right person beats a name-search lottery
        // that can land on a different person (Gabe Curtis vs Gabe Fraher).
        let runs = [run("Dark Divine - Topic", browseId: "UCtopic", pageType: topicPage)]
        #expect(ArtistCredits.parse(runs: runs) == [ArtistCredit(name: "Dark Divine", browseId: "UCtopic")])
    }

    @Test("similar names never share ids")
    func similarNamesKeptSeparate() {
        let runs = [
            run("Gabe Curtis", browseId: "UCRDeuDhZD8mZk42hL737pww", pageType: topicPage),
            run(" • "),
            run("Gabe Fraher", browseId: "UCYvJKFkndPSKzw-o0bLpekQ", pageType: topicPage)
        ]
        #expect(ArtistCredits.parse(runs: runs) == [
            ArtistCredit(name: "Gabe Curtis", browseId: "UCRDeuDhZD8mZk42hL737pww"),
            ArtistCredit(name: "Gabe Fraher", browseId: "UCYvJKFkndPSKzw-o0bLpekQ")
        ])
    }

    @Test("dedupes repeats, preferring the copy with an id")
    func dedupePrefersId() {
        let runs = [run("Dark Divine"), run(" • "), run("Dark Divine", browseId: "UCvg", pageType: artistPage)]
        #expect(ArtistCredits.parse(runs: runs) == [ArtistCredit(name: "Dark Divine", browseId: "UCvg")])
    }

    @Test("keeps plain channel links with their id")
    func plainChannelLink() {
        let runs = [run("Some Channel", browseId: "UCplain")]
        #expect(ArtistCredits.parse(runs: runs) == [ArtistCredit(name: "Some Channel", browseId: "UCplain")])
    }

    @Test("cleanedName strips topic and years")
    func cleanedName() {
        #expect(ArtistCredits.cleanedName("Dark Divine - Topic") == "Dark Divine")
        #expect(ArtistCredits.cleanedName("Rhiannon (2024)") == "Rhiannon")
        #expect(ArtistCredits.cleanedName("  Spaced  ") == "Spaced")
    }

    @Test("drops clock durations from bylines")
    func dropsDurations() {
        // Row bylines sometimes carry the length ("Video • Aria • 1:33:21");
        // it must never parse as an artist credit.
        let runs = [
            run("Video"), run(" • "),
            run("Aria", browseId: "UCn1icliVp7N5EcLosJ-zJXg"),
            run(" • "), run("1:33:21"), run(" • "), run("3:21")
        ]
        #expect(ArtistCredits.parse(runs: runs) == [
            ArtistCredit(name: "Aria", browseId: "UCn1icliVp7N5EcLosJ-zJXg")
        ])
    }

    @Test("isArtistName rejects separators and junk")
    func isArtistName() {
        #expect(!ArtistCredits.isArtistName(" & "))
        #expect(!ArtistCredits.isArtistName("Song"))
        #expect(!ArtistCredits.isArtistName("14K views"))
        #expect(!ArtistCredits.isArtistName("1:33:21"))
        #expect(ArtistCredits.isArtistName("Dark Divine"))
    }
}
