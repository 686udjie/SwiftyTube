//
//  MutationService.swift
//  SwiftyTube
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation

public actor MutationService {
    private let client: InnerTubeClient
    private let store: any LibrarySyncStore

    public init(client: InnerTubeClient, store: any LibrarySyncStore) {
        self.client = client
        self.store = store
    }

    private func emptySong(id: String, liked: Bool, addToken: String = "") -> SyncSong {
        SyncSong.skeleton(id: id, liked: liked, addToken: addToken)
    }

    private static let orphanRepairInterval: TimeInterval = 10 * 60
    private static let orphanRepairBatchSize = 10

    private var lastOrphanRepair: Date?
    private var unrecoverableOrphans = Set<String>()

    private func enrichEmptySong(_ song: SyncSong) async -> SyncSong {
        guard song.title.isEmpty else { return song }
        guard let metadata = try? await fetchSongMetadata(videoId: song.id) else { return song }
        return SyncSong.merging(song, with: metadata)
    }

    private func fetchSongMetadata(videoId: String) async throws -> SongMetadata? {
        let json = try await client.next(videoId: videoId)
        guard let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any],
              let tabbed = singleColumn["tabbedRenderer"] as? [String: Any],
              let watchNext = tabbed["watchNextTabbedResultsRenderer"] as? [String: Any],
              let tabs = watchNext["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let results = content["results"] as? [String: Any],
              let primary = results["primaryInfoRenderer"] as? [String: Any] else {
            return nil
        }

        let title = InnerTubeJSON.runsText(primary["title"] as? [String: Any]) ?? ""

        let secondary = results["secondaryInfoRenderer"] as? [String: Any]
        let byline = secondary?["videoOwnerRenderer"] as? [String: Any]
        let bylineRuns = InnerTubeJSON.rawRuns(byline?["title"] as? [String: Any])
        let artistName = bylineRuns.first.map { $0["text"] as? String } ?? nil

        let thumbnailDict = primary["thumbnail"] as? [String: Any]
        let thumbnails = thumbnailDict?["thumbnails"] as? [[String: Any]]
        let thumbnailUrl = thumbnails?.last?["url"] as? String

        let lengthSeconds = primary["lengthSeconds"] as? String
        let duration = lengthSeconds.flatMap { Int($0) } ?? 0

        return SongMetadata(title: title, artistName: artistName, thumbnailUrl: thumbnailUrl, duration: duration, albumName: nil)
    }

    public func repairOrphanSongs() async {
        if let last = lastOrphanRepair, Date().timeIntervalSince(last) < Self.orphanRepairInterval {
            return
        }
        lastOrphanRepair = Date()
        let orphans: [String]
        do {
            orphans = try await store.fetchOrphanSongIds().filter { !unrecoverableOrphans.contains($0) }
        } catch {
            return
        }
        guard !orphans.isEmpty else { return }
        for id in orphans.prefix(Self.orphanRepairBatchSize) {
            do {
                guard let metadata = try await fetchSongMetadata(videoId: id),
                      !metadata.title.isEmpty else {
                    unrecoverableOrphans.insert(id)
                    continue
                }
                let repaired = SyncSong.merging(
                    SyncSong.skeleton(id: id, liked: false),
                    with: metadata
                )
                try await store.insertSongIgnoringConflicts(repaired)
            } catch {
                continue
            }
        }
    }

    public func likeSong(videoId: String) async throws {
        var song: SyncSong
        if let existing = try await store.fetchSong(id: videoId) {
            song = existing
        } else {
            let skeleton = emptySong(id: videoId, liked: false)
            song = await enrichEmptySong(skeleton)
        }
        song.liked = true
        song.modifyDate = Date()
        try await store.saveSong(song)
        let applied = song
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.like(videoId: videoId) },
            rollback: {
                var restored = applied
                restored.liked = false
                try? await self.store.saveSong(restored)
            }
        )
    }

    public func unlikeSong(videoId: String) async throws {
        var song: SyncSong
        if let existing = try await store.fetchSong(id: videoId) {
            song = existing
        } else {
            let skeleton = emptySong(id: videoId, liked: true)
            song = await enrichEmptySong(skeleton)
        }
        song.liked = false
        song.modifyDate = Date()
        try await store.saveSong(song)
        let applied = song
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.unlike(videoId: videoId) },
            rollback: {
                var restored = applied
                restored.liked = true
                try? await self.store.saveSong(restored)
            }
        )
    }

    public func addToLibrary(videoId: String, addToken: String) async throws {
        var song: SyncSong
        if let existing = try await store.fetchSong(id: videoId) {
            song = existing
        } else {
            let skeleton = emptySong(id: videoId, liked: false, addToken: addToken)
            song = await enrichEmptySong(skeleton)
        }
        song.inLibrary = song.inLibrary ?? Date()
        song.modifyDate = Date()
        try await store.saveSong(song)
        let applied = song
        guard !addToken.isEmpty else { return }
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.feedback(tokens: [addToken]) },
            rollback: {
                var restored = applied
                restored.inLibrary = nil
                try? await self.store.saveSong(restored)
            }
        )
    }

    public func removeFromLibrary(videoId: String, removeToken: String) async throws {
        var song: SyncSong?
        if var existing = try await store.fetchSong(id: videoId) {
            existing.inLibrary = nil
            existing.modifyDate = Date()
            song = existing
            try await store.saveSong(existing)
        }
        guard !removeToken.isEmpty else { return }
        let applied = song
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.feedback(tokens: [removeToken]) },
            rollback: {
                if var restored = applied {
                    restored.inLibrary = Date()
                    restored.modifyDate = Date()
                    try? await self.store.saveSong(restored)
                }
            }
        )
    }

    public func addToPlaylist(playlistId: String, songId: String, setVideoId: String? = nil) async throws {
        let entity = try? await store.fetchPlaylist(id: playlistId)
        let isLocal = entity?.browseId == nil

        let entry = SyncPlaylistEntry(playlistId: playlistId, songId: songId, position: 0, setVideoId: setVideoId)
        try await store.insertMapIgnoringConflicts(entry)
        guard !isLocal else { return }

        let actions = PlaylistEditAction.dictionaries([.addVideo(videoId: songId, setVideoId: setVideoId)])
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.editPlaylist(playlistId: playlistId, actions: actions) },
            rollback: { try? await self.store.deleteMapEntry(playlistId: playlistId, songId: songId) }
        )
    }

    public func removeFromPlaylist(playlistId: String, songId: String, setVideoId: String) async throws {
        let entity = try? await store.fetchPlaylist(id: playlistId)
        let isLocal = entity?.browseId == nil

        if !isLocal {
            let actions = PlaylistEditAction.dictionaries([.removeVideo(setVideoId: setVideoId)])
            do {
                _ = try await client.editPlaylist(playlistId: playlistId, actions: actions)
            } catch {
                throw error
            }
        }

        try await store.deleteMapEntry(playlistId: playlistId, songId: songId)
    }

    public func createPlaylist(title: String, description: String? = nil) async throws -> String {
        let json = try await client.createPlaylist(title: title, description: description)
        guard let playlistId = PlaylistEditAction.extractPlaylistId(from: json) else {
            throw MutationError.playlistCreationFailed
        }
        let entity = SyncPlaylist(
            id: playlistId,
            browseId: "VL\(playlistId)",
            name: title,
            isEditable: true,
            bookmarkedAt: Date(),
            remoteSongCount: 0
        )
        _ = try await store.insertOrReplacePlaylist(entity)
        return playlistId
    }

    public func deletePlaylist(playlistId: String) async throws {
        let entity = try? await store.fetchPlaylist(id: playlistId)
        let isLocal = entity?.browseId == nil

        if !isLocal {
            do {
                _ = try await client.deletePlaylist(playlistId: playlistId)
            } catch {
                throw error
            }
        }

        try await store.deleteMapsForPlaylist(playlistId: playlistId)
        try await store.deletePlaylist(id: playlistId)
    }

    public func renamePlaylist(playlistId: String, newName: String) async throws {
        guard var entity = try? await store.fetchPlaylist(id: playlistId) else {
            throw NSError(domain: "MutationService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Playlist not found"])
        }

        let isLocal = entity.browseId == nil

        if !isLocal {
            let actions = PlaylistEditAction.dictionaries([.renamePlaylist(name: newName)])
            _ = try await client.editPlaylist(playlistId: playlistId, actions: actions)
        }

        entity.name = newName
        try await store.savePlaylist(entity)
    }

    public func subscribeArtist(channelId: String, artistId: String) async throws {
        var entity: SyncArtist?
        if var existing = try await store.fetchArtist(id: artistId) {
            existing.bookmarkedAt = Date()
            existing.channelId = channelId
            entity = existing
            try await store.saveArtist(existing)
        }
        let applied = entity
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.subscribe(channelId: channelId) },
            rollback: {
                if var restored = applied {
                    restored.bookmarkedAt = nil
                    restored.channelId = nil
                    try? await self.store.saveArtist(restored)
                }
            }
        )
    }

    public func unsubscribeArtist(channelId: String, artistId: String) async throws {
        var entity: SyncArtist?
        if var existing = try await store.fetchArtist(id: artistId) {
            existing.bookmarkedAt = nil
            entity = existing
            try await store.saveArtist(existing)
        }
        let applied = entity
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.unsubscribe(channelId: channelId) },
            rollback: {
                if var restored = applied {
                    restored.bookmarkedAt = restored.bookmarkedAt ?? Date()
                    try? await self.store.saveArtist(restored)
                }
            }
        )
    }

    // MARK: - Albums

    public func saveAlbum(
        browseId: String,
        title: String,
        thumbnailUrl: String? = nil,
        playlistId: String? = nil,
        songCount: Int = 0,
        duration: Int = 0,
        feedbackToken: String? = nil
    ) async throws {
        if var existing = try await store.fetchAlbum(id: browseId) {
            existing.bookmarkedAt = Date()
            if let thumbnailUrl { existing.thumbnailUrl = thumbnailUrl }
            if let playlistId { existing.playlistId = playlistId }
            if !title.isEmpty { existing.title = title }
            if songCount > 0 { existing.songCount = songCount }
            if duration > 0 { existing.duration = duration }
            try await store.saveAlbum(existing)
        } else {
            let entity = SyncAlbum(
                id: browseId,
                title: title,
                playlistId: playlistId,
                thumbnailUrl: thumbnailUrl,
                songCount: songCount,
                duration: duration,
                bookmarkedAt: Date()
            )
            try await store.saveAlbum(entity)
        }
        guard let token = feedbackToken, !token.isEmpty else { return }
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.feedback(tokens: [token]) },
            rollback: {
                if var restored = try? await self.store.fetchAlbum(id: browseId) {
                    restored.bookmarkedAt = nil
                    try? await self.store.saveAlbum(restored)
                }
            }
        )
    }

    public func unsaveAlbum(browseId: String, feedbackToken: String? = nil) async throws {
        var hadBookmark = false
        if var existing = try await store.fetchAlbum(id: browseId) {
            hadBookmark = existing.bookmarkedAt != nil
            existing.bookmarkedAt = nil
            try await store.saveAlbum(existing)
        }
        guard let token = feedbackToken, !token.isEmpty else { return }
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.feedback(tokens: [token]) },
            rollback: {
                if hadBookmark, var restored = try? await self.store.fetchAlbum(id: browseId) {
                    restored.bookmarkedAt = Date()
                    try? await self.store.saveAlbum(restored)
                }
            }
        )
    }

    // MARK: - Podcasts

    public func subscribePodcast(
        browseId: String,
        name: String,
        thumbnailUrl: String? = nil,
        channelId: String? = nil,
        feedbackToken: String? = nil
    ) async throws {
        if var existing = try await store.fetchPodcast(id: browseId) {
            existing.subscribedAt = Date()
            if !name.isEmpty { existing.name = name }
            if let thumbnailUrl { existing.thumbnailUrl = thumbnailUrl }
            try await store.savePodcast(existing)
        } else {
            let entity = SyncPodcast(
                id: browseId,
                name: name,
                thumbnailUrl: thumbnailUrl,
                subscribedAt: Date()
            )
            try await store.savePodcast(entity)
        }
        if feedbackToken == nil {
            let channel = channelId ?? browseId
            if !channel.isEmpty {
                // Best-effort remote subscribe; podcast channels share the subscription endpoint.
                _ = try? await client.subscribe(channelId: channel)
            }
            return
        }
        guard let token = feedbackToken, !token.isEmpty else { return }
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.feedback(tokens: [token]) },
            rollback: {
                if var restored = try? await self.store.fetchPodcast(id: browseId) {
                    restored.subscribedAt = nil
                    try? await self.store.savePodcast(restored)
                }
            }
        )
    }

    public func unsubscribePodcast(browseId: String, channelId: String? = nil, feedbackToken: String? = nil) async throws {
        if var existing = try await store.fetchPodcast(id: browseId) {
            existing.subscribedAt = nil
            try await store.savePodcast(existing)
        }
        if feedbackToken == nil {
            let channel = channelId ?? browseId
            if !channel.isEmpty {
                _ = try? await client.unsubscribe(channelId: channel)
            }
            return
        }
        guard let token = feedbackToken, !token.isEmpty else { return }
        try await OptimisticMutation.attemptingRemote(
            { _ = try await self.client.feedback(tokens: [token]) },
            rollback: {
                if var restored = try? await self.store.fetchPodcast(id: browseId) {
                    restored.subscribedAt = restored.subscribedAt ?? Date()
                    try? await self.store.savePodcast(restored)
                }
            }
        )
    }
}
