//
//  LibrarySyncService.swift
//  SwiftyTube
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation

public actor LibrarySyncService {
    private let client: InnerTubeClient
    private let store: any LibrarySyncStore
    private let playlistDetail: PlaylistDetailService

    public init(client: InnerTubeClient, store: any LibrarySyncStore) {
        self.client = client
        self.store = store
        self.playlistDetail = PlaylistDetailService(client: client, store: store)
    }

    public func syncAll(
        options: LibrarySyncOptions = LibrarySyncOptions(),
        onLikesRefresh: (@Sendable () async -> Void)? = nil
    ) async -> LibrarySyncResult {
        var result = LibrarySyncResult()
        if options.syncArtists {
            do {
                result.artistIds = try await syncSubscribedArtists()
                result.completedSections += 1
            } catch { SwiftyTubeLog.error("syncSubscribedArtists error: \(error)") }
        }
        if options.syncPlaylists {
            do {
                result.playlistIds = try await syncLikedPlaylists()
                result.completedSections += 1
            } catch { SwiftyTubeLog.error("syncLikedPlaylists error: \(error)") }
        }
        if options.syncAlbums {
            do {
                result.albumIds = try await syncSavedAlbums()
                result.completedSections += 1
            } catch { SwiftyTubeLog.error("syncSavedAlbums error: \(error)") }
        }
        if options.syncPodcasts {
            do {
                result.podcastIds = try await syncSubscribedPodcasts()
                result.completedSections += 1
            } catch { SwiftyTubeLog.error("syncPodcasts error: \(error)") }
        }
        if options.syncSongs {
            do {
                result.songIds = try await syncLikedSongs()
                result.completedSections += 1
            } catch { SwiftyTubeLog.error("syncLikedSongs error: \(error)") }
        }
        if let onLikesRefresh {
            await onLikesRefresh()
        }
        return result
    }
}

// MARK: Section sync

extension LibrarySyncService {
    public func syncSubscribedArtists() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_library_corpus_artists") { json in
            LibraryBrowseParser.parseArtists(from: json)
        }
        return try await store.applyArtistSync(items: items)
    }

    public func syncLikedPlaylists() async throws -> Set<String> {
        // YTM's Liked Music pseudo-playlist must never materialize as a
        // library row — its members merge into Liked Songs via syncLikedSongs.
        let likedMusicIds: Set<String> = ["LM", "VLLM"]
        let items = try await fetchAllPages(browseId: "FEmusic_liked_playlists") { json in
            LibraryBrowseParser.parsePlaylists(from: json).filter { !likedMusicIds.contains($0.browseId) }
        }
        return try await store.applyPlaylistSync(items: items)
    }

    public func syncSavedAlbums() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_liked_albums") { json in
            LibraryBrowseParser.parseAlbums(from: json)
        }
        return try await store.applyAlbumSync(items: items)
    }

    public func syncSubscribedPodcasts() async throws -> Set<String> {
        let items = try await fetchAllPages(browseId: "FEmusic_library_non_music_audio_list") { json in
            LibraryBrowseParser.parsePodcasts(from: json)
        }
        return try await store.applyPodcastSync(items: items)
    }

    /// Merges YTM's Liked Music auto-playlist (VLLM) into the permanent local
    /// Liked Songs list, like Metrolist. The LM playlist row itself is
    /// deleted right away so it never appears in the library.
    public func syncLikedSongs() async throws -> Set<String> {
        _ = try await playlistDetail.fetchPlaylist(playlistId: "LM")
        let orderedIds = try await store.likedPlaylistSongIdsOrdered(playlistId: "LM")
        let remoteIds = Set(orderedIds)
        if !orderedIds.isEmpty {
            // Mirror YTM's liked order in the local Liked Songs list, which
            // sorts by create_date: newest like first, staggered by shelf position.
            let base = Date()
            try await store.mirrorLikedSongs(orderedIds: orderedIds, baseDate: base)
            let graceCutoff = Date().addingTimeInterval(-5 * 60)
            try await store.unmarkStaleLikedSongs(excluding: remoteIds, graceCutoff: graceCutoff)
        }
        try await store.deletePlaylistRows(playlistId: "LM")
        return remoteIds
    }
}

// MARK: Pagination

extension LibrarySyncService {
    private func fetchAllPages<T>(
        browseId: String,
        params: String? = nil,
        parse: @escaping ([String: Any]) -> [T]
    ) async throws -> [T] {
        try await client.paginate(
            browseId: browseId,
            params: params,
            parse: parse,
            continuation: LibraryBrowseParser.extractContinuationToken(from:)
        )
    }
}
