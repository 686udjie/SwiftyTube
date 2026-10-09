//
//  LibrarySyncStore.swift
//  SwiftyTube
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation

/// App-side persistence for library sync. Implement with whatever store the
/// app uses (GRDB, Core Data, in-memory). All methods are called from the
/// sync actors; none of them perform network I/O.
public protocol LibrarySyncStore: Sendable {
    // MARK: - Library sections (batch merge + sweep)

    /// Upserts subscribed artists and clears bookmarks missing remotely.
    /// Returns the remote ids.
    func applyArtistSync(items: [ParsedArtist]) async throws -> Set<String>

    /// Upserts liked playlists (never materializing the Liked Music
    /// pseudo-playlist) and deletes auto-synced rows missing remotely.
    /// Returns the remote ids.
    func applyPlaylistSync(items: [ParsedPlaylist]) async throws -> Set<String>

    /// Upserts saved albums and clears bookmarks missing remotely.
    /// Returns the remote ids.
    func applyAlbumSync(items: [ParsedAlbum]) async throws -> Set<String>

    /// Upserts subscribed podcasts and clears subscriptions missing remotely.
    /// Returns the remote ids.
    func applyPodcastSync(items: [ParsedPodcast]) async throws -> Set<String>

    // MARK: - Liked songs (Liked Music auto-playlist merge)

    /// Song ids of a materialized playlist, in remote shelf order.
    func likedPlaylistSongIdsOrdered(playlistId: String) async throws -> [String]

    /// Mirrors the remote liked order into the permanent liked list.
    func mirrorLikedSongs(orderedIds: [String], baseDate: Date) async throws

    /// Clears the liked flag for songs missing remotely, sparing recently
    /// modified rows newer than `graceCutoff`.
    func unmarkStaleLikedSongs(excluding ids: Set<String>, graceCutoff: Date) async throws

    /// Deletes a materialized playlist's mappings and its playlist row.
    func deletePlaylistRows(playlistId: String) async throws

    // MARK: - Playlist contents

    func fetchPlaylist(id: String) async throws -> SyncPlaylist?
    func savePlaylist(_ playlist: SyncPlaylist) async throws
    func insertOrReplacePlaylist(_ playlist: SyncPlaylist) async throws -> SyncPlaylist
    func deletePlaylist(id: String) async throws
    func deleteMapsForPlaylist(playlistId: String) async throws
    func insertMapIgnoringConflicts(_ entry: SyncPlaylistEntry) async throws
    func fetchMapEntry(playlistId: String, songId: String) async throws -> SyncPlaylistEntry?
    func deleteMapEntry(playlistId: String, songId: String) async throws

    // MARK: - Songs

    func fetchSong(id: String) async throws -> SyncSong?
    func saveSong(_ song: SyncSong) async throws
    func insertSongIgnoringConflicts(_ song: SyncSong) async throws
    func fetchOrphanSongIds() async throws -> [String]

    // MARK: - Artists / albums / podcasts

    func fetchArtist(id: String) async throws -> SyncArtist?
    func saveArtist(_ artist: SyncArtist) async throws
    func fetchAlbum(id: String) async throws -> SyncAlbum?
    func saveAlbum(_ album: SyncAlbum) async throws
    func fetchPodcast(id: String) async throws -> SyncPodcast?
    func savePodcast(_ podcast: SyncPodcast) async throws
}
