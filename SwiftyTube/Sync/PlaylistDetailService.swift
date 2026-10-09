//
//  PlaylistDetailService.swift
//  SwiftyTube
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation

public actor PlaylistDetailService {
    private let client: InnerTubeClient
    private let store: any LibrarySyncStore

    public init(client: InnerTubeClient, store: any LibrarySyncStore) {
        self.client = client
        self.store = store
    }

    public func fetchPlaylist(playlistId: String, maxPages: Int = 100) async throws -> Int {
        let (_, snapshot) = try await fetchPlaylistRows(playlistId: playlistId, maxPages: maxPages)
        let browseId = Self.requestBrowseId(for: playlistId)
        let existing = try await store.fetchPlaylist(id: playlistId)
        let entity = SyncPlaylist.merging(
            existing: existing,
            id: playlistId,
            browseId: browseId,
            name: "Playlist",
            remoteSongCount: snapshot.count
        )
        try await store.savePlaylist(entity)

        // Clear existing song mappings and re-insert
        try await store.deleteMapsForPlaylist(playlistId: playlistId)
        var skipped = 0
        for (index, rawItem) in snapshot.enumerated() {
            guard let renderer = rawItem["musicResponsiveListItemRenderer"] as? [String: Any],
                  let videoId = Self.playlistRowVideoId(renderer) else {
                skipped += 1
                continue
            }
            let nav = renderer["navigationEndpoint"] as? [String: Any]
            let watch = nav?["watchEndpoint"] as? [String: Any]
            let setVideoId = watch?["playlistSetVideoId"] as? String

            if let songItem = LibraryBrowseParser.parseSong(rawItem) {
                let existing = try await store.fetchSong(id: videoId)
                let entity = SyncSong.merging(
                    existing: existing,
                    id: videoId,
                    title: songItem.title,
                    artistName: songItem.artists.first,
                    albumName: songItem.album,
                    duration: songItem.duration,
                    thumbnailUrl: songItem.thumbnailUrl
                )
                try await store.saveSong(entity)
            }

            try await store.insertMapIgnoringConflicts(SyncPlaylistEntry(
                playlistId: playlistId,
                songId: videoId,
                position: index,
                setVideoId: setVideoId
            ))
        }
        if skipped > 0 {
            SwiftyTubeLog.debug("fetchPlaylist \(playlistId): skipped \(skipped)/\(snapshot.count) rows without video id")
        }
        return snapshot.count
    }

    /// All raw track rows across every page, plus the first page's JSON for
    /// header parsing. Markers are stripped; each row carries a
    /// `musicResponsiveListItemRenderer`.
    public func fetchPlaylistRows(playlistId: String, maxPages: Int = 100) async throws -> (firstPage: [String: Any], rows: [[String: Any]]) {
        // Stored ids may already carry the prefix (library rows keep the
        // endpoint's VL… id); blindly prepending yields VLVL… and the server
        // answers with a content-less response.
        let browseId = Self.requestBrowseId(for: playlistId)
        var allItems: [[String: Any]] = []
        var token: String?
        var seenTokens = Set<String>()
        var pages = 0
        var hadShelf = false
        var firstPage: [String: Any]?
        repeat {
            // Continuation requests carry only the token; resending browseId
            // makes the server ignore it and return page one again.
            let json: [String: Any]
            if let token {
                json = try await client.browse(continuation: token)
            } else {
                json = try await client.browse(browseId: browseId)
            }
            if firstPage == nil {
                firstPage = json
            }
            if let items = extractPlaylistItems(from: json) {
                hadShelf = true
                allItems += items
            }
            token = extractPlaylistContinuation(from: json)
            pages += 1
            if let token, !seenTokens.insert(token).inserted {
                SwiftyTubeLog.error("fetchPlaylist \(playlistId): repeated continuation token, stopping")
                break
            }
            if pages >= maxPages {
                SwiftyTubeLog.error("fetchPlaylist \(playlistId): hit \(maxPages)-page cap, stopping")
                break
            }
        } while token != nil

        guard hadShelf, let firstPage else {
            throw InnerTubeError.invalidResponse
        }
        return (firstPage, allItems)
    }

    /// Endpoint browse id for a playlist, tolerating ids that already carry
    /// the VL prefix (library rows store the endpoint's id verbatim).
    static func requestBrowseId(for playlistId: String) -> String {
        playlistId.hasPrefix("VL") ? playlistId : "VL\(playlistId)"
    }

    private static func playlistRowVideoId(_ renderer: [String: Any]) -> String? {
        if let videoId = renderer["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        if let itemData = renderer["playlistItemData"] as? [String: Any],
           let videoId = itemData["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        if let nav = renderer["navigationEndpoint"] as? [String: Any],
           let watch = nav["watchEndpoint"] as? [String: Any],
           let videoId = watch["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        if let overlay = renderer["overlay"] as? [String: Any],
           let overlayRenderer = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
           let content = overlayRenderer["content"] as? [String: Any],
           let playButton = content["musicPlayButtonRenderer"] as? [String: Any],
           let nav = playButton["playNavigationEndpoint"] as? [String: Any],
           let watch = nav["watchEndpoint"] as? [String: Any],
           let videoId = watch["videoId"] as? String, !videoId.isEmpty {
            return videoId
        }
        return nil
    }

    func extractPlaylistItems(from json: [String: Any]) -> [[String: Any]]? {
        var foundShelf = false
        var rows: [[String: Any]] = []
        for shelf in playlistShelves(from: json) {
            guard let contents = shelf["contents"] as? [[String: Any]] else { continue }
            foundShelf = true
            rows += trackRows(contents)
        }
        if foundShelf {
            return rows
        }
        // Continuation pages for large/private playlists arrive with no shelf
        // at all: rows live in
        // onResponseReceivedActions[].appendContinuationItemsAction.continuationItems.
        let actionItems = continuationActionItems(from: json)
        if !actionItems.isEmpty {
            return trackRows(actionItems)
        }
        return nil
    }

    func extractPlaylistContinuation(from json: [String: Any]) -> String? {
        // Shelf-level tokens first: a sectionList-level token points at the
        // next *section* (a carousel), not at more tracks, and following it
        // strands large playlists at exactly page one.
        if let token = shelfContinuationToken(in: playlistShelves(from: json)) {
            return token
        }
        // Next-page token carried by a trailing continuationItemRenderer
        // inside appendContinuationItemsAction continuationItems.
        let actionItems = continuationActionItems(from: json)
        if !actionItems.isEmpty,
           let token = trailingContinuationToken(in: actionItems) {
            return token
        }
        // Last resort: sectionList-level token. This usually addresses the
        // next section rather than more tracks.
        if let twoCol = (json["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any],
           let secondary = twoCol["secondaryContents"] as? [String: Any],
           let sectionList = secondary["sectionListRenderer"] as? [String: Any],
           let continuations = sectionList["continuations"] as? [[String: Any]],
           let first = continuations.first,
           let next = first["nextContinuationData"] as? [String: Any],
           let token = next["continuation"] as? String {
            return token
        }
        return nil
    }

    /// Every candidate track shelf in a playlist response, in priority order:
    /// first-page shelf, two-column shelves, classic continuations.
    private func playlistShelves(from json: [String: Any]) -> [[String: Any]] {
        var shelves: [[String: Any]] = []
        if let firstSection = BrowseLens.firstBrowseSection(json),
           let shelf = (firstSection["musicPlaylistShelfRenderer"] as? [String: Any])
            ?? (firstSection["musicShelfRenderer"] as? [String: Any]) {
            shelves.append(shelf)
        }
        shelves += twoColumnShelves(from: json)
        if let continuationContents = json["continuationContents"] as? [String: Any] {
            for key in ["musicPlaylistShelfContinuation", "musicShelfContinuation"] {
                if let shelf = continuationContents[key] as? [String: Any] {
                    shelves.append(shelf)
                }
            }
        }
        return shelves
    }

    /// First shelf-level continuation token, preferring `continuations[]`
    /// over trailing markers within each shelf.
    private func shelfContinuationToken(in shelves: [[String: Any]]) -> String? {
        for shelf in shelves {
            if let token = InnerTubeDecode.continuationToken(in: shelf) {
                return token
            }
            if let token = trailingContinuationToken(in: shelf["contents"] as? [[String: Any]]) {
                return token
            }
        }
        return nil
    }

    /// Every song shelf from a twoColumnBrowseResultsRenderer response
    /// (secondaryContents → sectionListRenderer), unwrapping
    /// itemSectionRenderer wrappers like the detail parser does.
    private func twoColumnShelves(from json: [String: Any]) -> [[String: Any]] {
        guard let twoCol = (json["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any],
              let secondary = twoCol["secondaryContents"] as? [String: Any],
              let sectionList = secondary["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]] else { return [] }
        var shelves: [[String: Any]] = []
        for section in sections {
            let unwrapped = (section["itemSectionRenderer"] as? [String: Any])
                .flatMap { ($0["contents"] as? [[String: Any]])?.first }
                ?? section
            if let shelf = (unwrapped["musicPlaylistShelfRenderer"] as? [String: Any])
                ?? (unwrapped["musicShelfRenderer"] as? [String: Any]) {
                shelves.append(shelf)
            }
        }
        return shelves
    }

    /// Rows delivered outside any shelf: later continuation pages arrive as
    /// `onResponseReceivedActions[].appendContinuationItemsAction
    /// .continuationItems` with no `continuationContents` at all.
    private func continuationActionItems(from json: [String: Any]) -> [[String: Any]] {
        let actions = (json["onResponseReceivedActions"] as? [[String: Any]] ?? [])
            + (json["onResponseReceivedEndpoints"] as? [[String: Any]] ?? [])
        var out: [[String: Any]] = []
        for action in actions {
            guard let append = action["appendContinuationItemsAction"] as? [String: Any],
                  let items = append["continuationItems"] as? [[String: Any]] else { continue }
            out += items
        }
        return out
    }

    /// Next-page token carried by a trailing `continuationItemRenderer`
    /// (`continuationEndpoint.continuationCommand.token`, occasionally nested
    /// in `commandExecutorCommand.commands[]` alongside other commands).
    /// Shelf `continuations[]` are handled by InnerTubeDecode separately.
    private func trailingContinuationToken(in items: [[String: Any]]?) -> String? {
        guard let items else { return nil }
        for item in items {
            guard let renderer = item["continuationItemRenderer"] as? [String: Any],
                  let endpoint = renderer["continuationEndpoint"] as? [String: Any] else { continue }
            if let command = endpoint["continuationCommand"] as? [String: Any],
               let token = command["token"] as? String, !token.isEmpty {
                return token
            }
            // Token nested in a commandExecutorCommand list.
            if let executor = endpoint["commandExecutorCommand"] as? [String: Any],
               let commands = executor["commands"] as? [[String: Any]] {
                for command in commands {
                    guard let continuation = command["continuationCommand"] as? [String: Any],
                          let request = continuation["request"] as? String,
                          request == "CONTINUATION_REQUEST_TYPE_BROWSE",
                          let token = continuation["token"] as? String, !token.isEmpty else { continue }
                    return token
                }
            }
        }
        return nil
    }

    /// Drops `continuationItemRenderer` entries (page markers, not tracks).
    private func trackRows(_ items: [[String: Any]]) -> [[String: Any]] {
        items.filter { $0["continuationItemRenderer"] == nil }
    }
}
