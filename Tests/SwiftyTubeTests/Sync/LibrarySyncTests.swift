//
//  LibrarySyncTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

// MARK: - Fixtures

private func flexColumn(_ runs: [String]) -> [String: Any] {
    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": runs.map { ["text": $0] }]]]
}

private func listItem(
    title: String,
    subtitle: [String] = [],
    browseId: String? = nil,
    videoId: String? = nil,
    menu: [String: Any]? = nil
) -> [String: Any] {
    var renderer: [String: Any] = [
        "flexColumns": [flexColumn([title]), flexColumn(subtitle)],
        "thumbnail": ["musicThumbnailRenderer": ["thumbnail": ["thumbnails": [["url": "https://x/y.jpg"]]]]]
    ]
    if let browseId {
        renderer["navigationEndpoint"] = ["browseEndpoint": ["browseId": browseId]]
    }
    if let videoId {
        renderer["videoId"] = videoId
    }
    if let menu {
        renderer["menu"] = menu
    }
    return ["musicResponsiveListItemRenderer": renderer]
}

private func shelfResponse(items: [[String: Any]], token: String? = nil) -> [String: Any] {
    var shelf: [String: Any] = ["contents": items]
    if let token {
        shelf["continuations"] = [["nextContinuationData": ["continuation": token]]]
    }
    return [
        "contents": [
            "singleColumnBrowseResultsRenderer": [
                "tabs": [[
                    "tabRenderer": [
                        "content": [
                            "sectionListRenderer": [
                                "contents": [[
                                    "itemSectionRenderer": [
                                        "contents": [["musicShelfRenderer": shelf]]
                                    ]
                                ]]
                            ]
                        ]
                    ]
                ]]
            ]
        ]
    ]
}

// MARK: - Parser tests

@Suite("Library browse parsing")
struct LibraryBrowseParserTests {
    @Test("Artists parse with continuation")
    func artists() {
        let json = shelfResponse(items: [
            listItem(title: "Boards of Canada", subtitle: ["Artist"], browseId: "UCx"),
            listItem(title: "No Endpoint Row", subtitle: ["Artist"])
        ], token: "next-page")
        let artists = LibraryBrowseParser.parseArtists(from: json)
        #expect(artists.count == 1)
        #expect(artists[0].browseId == "UCx")
        #expect(artists[0].name == "Boards of Canada")
        #expect(LibraryBrowseParser.extractContinuationToken(from: json) == "next-page")
    }

    @Test("Playlists skip rows without browse id")
    func playlists() {
        let json = shelfResponse(items: [
            listItem(title: "Gym", subtitle: ["Playlist", "42"], browseId: "VLPL1")
        ])
        let playlists = LibraryBrowseParser.parsePlaylists(from: json)
        #expect(playlists.count == 1)
        #expect(playlists[0].songCount == 42)
        #expect(LibraryBrowseParser.extractContinuationToken(from: json) == nil)
    }

    @Test("Song keeps title and first artist")
    func song() {
        let item = listItem(
            title: "Dayvan Cowboy",
            subtitle: ["Boards of Canada", " • ", "The Campfire Headphase"],
            videoId: "abc123"
        )
        let song = LibraryBrowseParser.parseSong(item)
        #expect(song?.videoId == "abc123")
        #expect(song?.title == "Dayvan Cowboy")
        #expect(song?.artists.first == "Boards of Canada")
    }

    @Test("Albums and podcasts parse")
    func albumsAndPodcasts() {
        let albumJson = shelfResponse(items: [
            listItem(title: "Geogaddi", subtitle: ["Album", "Boards of Canada"], browseId: "MPREb_x")
        ])
        let albums = LibraryBrowseParser.parseAlbums(from: albumJson)
        #expect(albums.count == 1)
        #expect(albums[0].browseId == "MPREb_x")

        let podcastJson = shelfResponse(items: [
            listItem(title: "My Podcast", subtitle: ["Podcast"], browseId: "MPSP_x")
        ])
        let podcasts = LibraryBrowseParser.parsePodcasts(from: podcastJson)
        #expect(podcasts.count == 1)
        #expect(podcasts[0].name == "My Podcast")
    }

    @Test("Like toggle tokens surface isLiked")
    func likeToggle() {
        let menu: [String: Any] = ["menuRenderer": ["items": [[
            "toggleMenuServiceItemRenderer": [
                "defaultIcon": ["iconType": "CHECK_CHECK"],
                "defaultServiceEndpoint": ["feedbackEndpoint": ["feedbackToken": "add-tok"]],
                "toggledServiceEndpoint": ["feedbackEndpoint": ["feedbackToken": "remove-tok"]]
            ]
        ]]]]
        let item = listItem(title: "Loved", subtitle: ["Artist"], videoId: "v1", menu: menu)
        let song = LibraryBrowseParser.parseSong(item)
        #expect(song?.isLiked == true)
        #expect(song?.libraryAddToken == "add-tok")
        #expect(song?.libraryRemoveToken == "remove-tok")
    }
}

@Suite("Browse lens")
struct BrowseLensTests {
    @Test("Sections and account runs")
    func sections() {
        let json = shelfResponse(items: [listItem(title: "A", browseId: "UC1")])
        #expect(BrowseLens.browseSections(json)?.count == 1)
        #expect(BrowseLens.firstBrowseSection(json) != nil)
        #expect(BrowseLens.firstSectionItem(json) != nil)

        let account: [String: Any] = ["header": ["musicAccountHeaderRenderer": [
            "accountName": ["runs": [["text": "Ada"]]]
        ]]]
        #expect(BrowseLens.accountNameRuns(account)?.count == 1)
        #expect(BrowseLens.accountNameRuns([:]) == nil)
    }
}

// MARK: - Store value tests

@Suite("Sync store values")
struct SyncValueTests {
    @Test("Skeleton starts empty and unliked")
    func skeleton() {
        let song = SyncSong.skeleton(id: "v", liked: false)
        #expect(song.title.isEmpty)
        #expect(song.liked == false)
        #expect(song.duration == 0)
    }

    @Test("Merging preserves stored state")
    func merging() {
        let stored = SyncSong.skeleton(id: "v", liked: true)
        var storedLiked = stored
        storedLiked.title = "Kept"
        storedLiked.totalPlayTime = 99
        let merged = SyncSong.merging(
            existing: storedLiked, id: "v", title: "Fresh",
            artistName: "New Artist", albumName: nil, duration: 0,
            thumbnailUrl: "https://x/new.jpg"
        )
        #expect(merged.title == "Fresh")
        #expect(merged.liked == true)
        #expect(merged.totalPlayTime == 99)
        #expect(merged.artistName == "New Artist")
        #expect(merged.thumbnailUrl == "https://x/new.jpg")
    }

    @Test("Metadata fills only blanks")
    func metadata() {
        var song = SyncSong.skeleton(id: "v", liked: false)
        song.artistName = "Stored"
        let enriched = SyncSong.merging(
            song, with: SongMetadata(title: "T", artistName: "Meta", thumbnailUrl: "https://x/m.jpg", duration: 200, albumName: nil)
        )
        #expect(enriched.title == "T")
        #expect(enriched.artistName == "Stored")
        #expect(enriched.duration == 200)
    }

    @Test("Playlist merging keeps the user's name")
    func playlist() {
        let existing = SyncPlaylist(id: "PL1", browseId: "VLPL1", name: "Mine", isEditable: true, bookmarkedAt: Date(), remoteSongCount: 3)
        let merged = SyncPlaylist.merging(existing: existing, id: "PL1", browseId: "VLPL1", name: "Remote", remoteSongCount: 5)
        #expect(merged.name == "Mine")
        #expect(merged.remoteSongCount == 5)
    }
}

// MARK: - Sync gating test

actor MockSyncStore: LibrarySyncStore {
    var appliedSections: [String] = []

    func applyArtistSync(items: [ParsedArtist]) async throws -> Set<String> {
        appliedSections.append("artists")
        return Set(items.map(\.browseId))
    }

    func applyPlaylistSync(items: [ParsedPlaylist]) async throws -> Set<String> {
        appliedSections.append("playlists")
        return Set(items.map(\.browseId))
    }

    func applyAlbumSync(items: [ParsedAlbum]) async throws -> Set<String> {
        appliedSections.append("albums")
        return Set(items.map(\.browseId))
    }

    func applyPodcastSync(items: [ParsedPodcast]) async throws -> Set<String> {
        appliedSections.append("podcasts")
        return Set(items.map(\.browseId))
    }

    func likedPlaylistSongIdsOrdered(playlistId: String) async throws -> [String] { [] }
    func mirrorLikedSongs(orderedIds: [String], baseDate: Date) async throws {}
    func unmarkStaleLikedSongs(excluding ids: Set<String>, graceCutoff: Date) async throws {}
    func deletePlaylistRows(playlistId: String) async throws {}
    func fetchPlaylist(id: String) async throws -> SyncPlaylist? { nil }
    func savePlaylist(_ playlist: SyncPlaylist) async throws {}
    func insertOrReplacePlaylist(_ playlist: SyncPlaylist) async throws -> SyncPlaylist { playlist }
    func deletePlaylist(id: String) async throws {}
    func deleteMapsForPlaylist(playlistId: String) async throws {}
    func insertMapIgnoringConflicts(_ entry: SyncPlaylistEntry) async throws {}
    func fetchMapEntry(playlistId: String, songId: String) async throws -> SyncPlaylistEntry? { nil }
    func deleteMapEntry(playlistId: String, songId: String) async throws {}
    func fetchSong(id: String) async throws -> SyncSong? { nil }
    func saveSong(_ song: SyncSong) async throws {}
    func insertSongIgnoringConflicts(_ song: SyncSong) async throws {}
    func fetchOrphanSongIds() async throws -> [String] { [] }
    func fetchArtist(id: String) async throws -> SyncArtist? { nil }
    func saveArtist(_ artist: SyncArtist) async throws {}
    func fetchAlbum(id: String) async throws -> SyncAlbum? { nil }
    func saveAlbum(_ album: SyncAlbum) async throws {}
    func fetchPodcast(id: String) async throws -> SyncPodcast? { nil }
    func savePodcast(_ podcast: SyncPodcast) async throws {}
}

@Suite("Playlist continuation shapes")
struct PlaylistContinuationTests {
    private func service() -> PlaylistDetailService {
        PlaylistDetailService(client: InnerTubeClient(config: .music), store: MockSyncStore())
    }

    private func track(_ videoId: String) -> [String: Any] {
        listItem(title: "Track \(videoId)", subtitle: ["Artist"], videoId: videoId)
    }

    private func continuationItem(token: String) -> [String: Any] {
        ["continuationItemRenderer": [
            "continuationEndpoint": ["continuationCommand": ["token": token]]
        ]]
    }

    private func actionPage(_ items: [[String: Any]]) -> [String: Any] {
        ["onResponseReceivedActions": [[
            "appendContinuationItemsAction": ["continuationItems": items]
        ]]]
    }

    /// Real VL playlist envelope: twoColumn → secondaryContents →
    /// sectionListRenderer → musicPlaylistShelfRenderer.
    private func playlistPage(_ shelfContents: [[String: Any]], continuations: [[String: Any]]? = nil) -> [String: Any] {
        var shelf: [String: Any] = ["contents": shelfContents]
        if let continuations { shelf["continuations"] = continuations }
        return ["contents": ["twoColumnBrowseResultsRenderer": ["secondaryContents": ["sectionListRenderer": ["contents": [
            ["musicPlaylistShelfRenderer": shelf]
        ]]]]]]
    }

    @Test("First page drops the trailing continuation marker but keeps its token")
    func firstPage() async {
        let json = playlistPage([track("v1"), track("v2"), continuationItem(token: "tok2")])
        let service = service()
        let items = await service.extractPlaylistItems(from: json)
        #expect(items?.count == 2)
        #expect(await service.extractPlaylistContinuation(from: json) == "tok2")
    }

    @Test("Later pages read rows and token from appendContinuationItemsAction")
    func laterPage() async {
        let json = actionPage([track("v101"), track("v102"), continuationItem(token: "tok3")])
        let service = service()
        let items = await service.extractPlaylistItems(from: json)
        #expect(items?.count == 2)
        #expect(await service.extractPlaylistContinuation(from: json) == "tok3")
    }

    @Test("Terminal page yields rows and no token")
    func terminalPage() async {
        let json = actionPage([track("v120")])
        let service = service()
        #expect(await service.extractPlaylistItems(from: json)?.count == 1)
        #expect(await service.extractPlaylistContinuation(from: json) == nil)
    }

    @Test("Shelf continuations array still wins")
    func shelfContinuations() async {
        let json = playlistPage(
            [track("v1")],
            continuations: [["nextContinuationData": ["continuation": "shelf-tok"]]]
        )
        let service = service()
        #expect(await service.extractPlaylistContinuation(from: json) == "shelf-tok")
    }

    @Test("Unknown shape yields nothing")
    func unknown() async {
        let service = service()
        #expect(await service.extractPlaylistItems(from: [:]) == nil)
        #expect(await service.extractPlaylistContinuation(from: [:]) == nil)
    }

    @Test("Browse id tolerates ids that already carry the VL prefix")
    func browseIdPrefix() {
        #expect(PlaylistDetailService.requestBrowseId(for: "PLabc") == "VLPLabc")
        #expect(PlaylistDetailService.requestBrowseId(for: "VLPLabc") == "VLPLabc")
    }

    @Test("Token nested in commandExecutorCommand is found")
    func executorToken() async {
        let nested: [String: Any] = ["continuationItemRenderer": [
            "continuationEndpoint": ["commandExecutorCommand": ["commands": [
                ["playlistVotingRefreshPopupCommand": [:]],
                ["continuationCommand": ["request": "CONTINUATION_REQUEST_TYPE_BROWSE", "token": "exec-tok"]]
            ]]]
        ]]
        let json = playlistPage([track("v1"), nested])
        let service = service()
        #expect(await service.extractPlaylistItems(from: json)?.count == 1)
        #expect(await service.extractPlaylistContinuation(from: json) == "exec-tok")
    }
}

@Suite("Regional charts")
struct RegionalChartsTests {
    private func chartsResponse(items: [[String: Any]]) -> [String: Any] {
        ["contents": ["singleColumnBrowseResultsRenderer": ["tabs": [[
            "tabRenderer": ["content": ["sectionListRenderer": ["contents": [[
                "musicCarouselShelfRenderer": [
                    "header": ["musicCarouselShelfBasicHeaderRenderer": ["title": ["runs": [["text": "Videos"]]]]],
                    "contents": items
                ]
            ]]]]]
        ]]]]]
    }

    private func twoRowPlaylist(title: String, browseId: String) -> [String: Any] {
        ["musicTwoRowItemRenderer": [
            "title": ["runs": [["text": title]]],
            "navigationEndpoint": ["browseEndpoint": ["browseId": browseId]]
        ]]
    }

    @Test("Prefers the Trending playlist, then daily, then first")
    func selection() {
        let entries = [
            (id: "VLPL-daily", title: "Daily Top Music Videos - Japan"),
            (id: "VLOLA-trending", title: "Trending 20 Japan"),
            (id: "VLPL-other", title: "Top 100 Japan")
        ]
        #expect(RegionalCharts.selectTrending(from: entries) == "VLOLA-trending")
        #expect(RegionalCharts.selectTrending(from: Array(entries.dropFirst())) == "VLOLA-trending")
        #expect(RegionalCharts.selectTrending(from: [entries[2]]) == "VLPL-other")
        #expect(RegionalCharts.selectTrending(from: []) == nil)
    }

    @Test("Parses playlist entries from charts carousels")
    func entries() {
        let json = chartsResponse(items: [
            twoRowPlaylist(title: "Trending 20 Japan", browseId: "VLOLA-trending"),
            twoRowPlaylist(title: "Daily Top Music Videos - Japan", browseId: "VLPL-daily"),
            ["musicResponsiveListItemRenderer": ["flexColumns": []]]
        ])
        let entries = RegionalCharts.playlistEntries(in: json)
        #expect(entries.map(\.id) == ["VLOLA-trending", "VLPL-daily"])
        #expect(RegionalCharts.selectTrending(from: entries) == "VLOLA-trending")
    }

    @Test("Unknown shapes yield nothing")
    func unknownCharts() {
        #expect(RegionalCharts.playlistEntries(in: [:]).isEmpty)
    }
}

@Suite("Library sync gating")
struct LibrarySyncGatingTests {
    @Test("Disabled sections skip network but still refresh likes")
    func disabledSections() async {
        let store = MockSyncStore()
        let service = LibrarySyncService(client: InnerTubeClient(config: .music), store: store)
        var refreshed = false
        let result = await service.syncAll(
            options: LibrarySyncOptions(syncArtists: false, syncPlaylists: false, syncAlbums: false, syncPodcasts: false, syncSongs: false),
            onLikesRefresh: { refreshed = true }
        )
        #expect(result.completedSections == 0)
        #expect(refreshed == true)
        #expect(await store.appliedSections.isEmpty)
    }
}
