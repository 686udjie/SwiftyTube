//
//  LibrarySyncModels.swift
//  SwiftyTube
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation

/// Which library sections a full sync covers. Apps build this from their own
/// settings (Trop maps its five sync toggles onto it).
public struct LibrarySyncOptions: Sendable, Hashable {
    public var syncArtists: Bool
    public var syncPlaylists: Bool
    public var syncAlbums: Bool
    public var syncPodcasts: Bool
    public var syncSongs: Bool

    public init(
        syncArtists: Bool = true,
        syncPlaylists: Bool = true,
        syncAlbums: Bool = true,
        syncPodcasts: Bool = true,
        syncSongs: Bool = true
    ) {
        self.syncArtists = syncArtists
        self.syncPlaylists = syncPlaylists
        self.syncAlbums = syncAlbums
        self.syncPodcasts = syncPodcasts
        self.syncSongs = syncSongs
    }
}

/// Per-section remote ids collected by a full sync.
public struct LibrarySyncResult: Sendable {
    public var artistIds: Set<String> = []
    public var playlistIds: Set<String> = []
    public var albumIds: Set<String> = []
    public var podcastIds: Set<String> = []
    public var songIds: Set<String> = []
    public var completedSections = 0

    public init() {}
}

/// Fetched song metadata used to fill skeleton songs.
public struct SongMetadata: Sendable {
    public let title: String
    public var artistName: String?
    public var thumbnailUrl: String?
    public var duration: Int
    public var albumName: String?

    public init(title: String, artistName: String?, thumbnailUrl: String?, duration: Int, albumName: String?) {
        self.title = title
        self.artistName = artistName
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.albumName = albumName
    }
}

/// A stored song row, without any database framework attached.
public struct SyncSong: Sendable, Hashable {
    public var id: String
    public var title: String
    public var artistName: String?
    public var albumName: String?
    public var duration: Int
    public var thumbnailUrl: String?
    public var liked: Bool
    public var totalPlayTime: Int64
    public var inLibrary: Date?
    public var libraryAddToken: String
    public var libraryRemoveToken: String
    public var isEpisode: Bool
    public var isUploaded: Bool
    public var isVideo: Bool
    public var createDate: Date
    public var modifyDate: Date

    public init(
        id: String,
        title: String,
        artistName: String?,
        albumName: String?,
        duration: Int,
        thumbnailUrl: String?,
        liked: Bool,
        totalPlayTime: Int64,
        inLibrary: Date?,
        libraryAddToken: String,
        libraryRemoveToken: String,
        isEpisode: Bool,
        isUploaded: Bool,
        isVideo: Bool,
        createDate: Date,
        modifyDate: Date
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.thumbnailUrl = thumbnailUrl
        self.liked = liked
        self.totalPlayTime = totalPlayTime
        self.inLibrary = inLibrary
        self.libraryAddToken = libraryAddToken
        self.libraryRemoveToken = libraryRemoveToken
        self.isEpisode = isEpisode
        self.isUploaded = isUploaded
        self.isVideo = isVideo
        self.createDate = createDate
        self.modifyDate = modifyDate
    }
}

// swiftlint:disable function_parameter_count
extension SyncSong {
    /// Empty placeholder for a song the store has never seen. Filled in later
    /// from fetched metadata; never surfaced to callers as-is.
    public static func skeleton(id: String, liked: Bool, addToken: String = "") -> SyncSong {
        SyncSong(
            id: id, title: "", artistName: nil, albumName: nil,
            duration: 0, thumbnailUrl: nil,
            liked: liked, totalPlayTime: 0, inLibrary: nil,
            libraryAddToken: addToken, libraryRemoveToken: "",
            isEpisode: false, isUploaded: false, isVideo: false,
            createDate: Date(), modifyDate: Date()
        )
    }

    /// Fills empty fields from metadata, preserving stored values. Does not
    /// touch `modifyDate` — callers that persist set it explicitly.
    public static func merging(_ song: SyncSong, with metadata: SongMetadata) -> SyncSong {
        var enriched = song
        if enriched.title.isEmpty {
            enriched.title = metadata.title
        }
        enriched.artistName = enriched.artistName ?? metadata.artistName
        enriched.thumbnailUrl = enriched.thumbnailUrl ?? metadata.thumbnailUrl
        if enriched.duration == 0 {
            enriched.duration = metadata.duration
        }
        enriched.albumName = enriched.albumName ?? metadata.albumName
        return enriched
    }

    /// Merges freshly fetched metadata over the stored row, preserving user
    /// state (liked, play time, library flags, tokens, original createDate).
    /// Unknown incoming values (empty title parts, zero duration, nil artwork)
    /// fall back to the stored row instead of wiping it.
    public static func merging(
        existing: SyncSong?,
        id: String,
        title: String,
        artistName: String?,
        albumName: String?,
        duration: Int,
        thumbnailUrl: String?,
        liked: Bool = false,
        libraryAddToken: String = "",
        libraryRemoveToken: String = "",
        isEpisode: Bool = false,
        isUploaded: Bool = false,
        isVideo: Bool = false
    ) -> SyncSong {
        SyncSong(
            id: id,
            title: title,
            artistName: existing?.artistName ?? artistName,
            albumName: existing?.albumName ?? albumName,
            duration: duration > 0 ? duration : existing?.duration ?? 0,
            thumbnailUrl: thumbnailUrl ?? existing?.thumbnailUrl,
            liked: existing?.liked ?? liked,
            totalPlayTime: existing?.totalPlayTime ?? 0,
            inLibrary: existing?.inLibrary,
            libraryAddToken: existing?.libraryAddToken ?? libraryAddToken,
            libraryRemoveToken: existing?.libraryRemoveToken ?? libraryRemoveToken,
            isEpisode: existing?.isEpisode ?? isEpisode,
            isUploaded: existing?.isUploaded ?? isUploaded,
            isVideo: existing?.isVideo ?? isVideo,
            createDate: existing?.createDate ?? Date(),
            modifyDate: Date()
        )
    }
}
// swiftlint:enable function_parameter_count

/// A stored artist row.
public struct SyncArtist: Sendable, Hashable {
    public var id: String
    public var name: String
    public var thumbnailUrl: String?
    public var bookmarkedAt: Date?
    public var isPodcastChannel: Bool
    public var channelId: String?

    public init(id: String, name: String, thumbnailUrl: String?, bookmarkedAt: Date?, isPodcastChannel: Bool, channelId: String?) {
        self.id = id
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.bookmarkedAt = bookmarkedAt
        self.isPodcastChannel = isPodcastChannel
        self.channelId = channelId
    }
}

/// A stored album row.
public struct SyncAlbum: Sendable, Hashable {
    public var id: String
    public var title: String
    public var playlistId: String?
    public var thumbnailUrl: String?
    public var songCount: Int
    public var duration: Int
    public var bookmarkedAt: Date?
    public var isUploaded: Bool

    public init(
        id: String,
        title: String,
        playlistId: String?,
        thumbnailUrl: String?,
        songCount: Int,
        duration: Int,
        bookmarkedAt: Date?,
        isUploaded: Bool = false
    ) {
        self.id = id
        self.title = title
        self.playlistId = playlistId
        self.thumbnailUrl = thumbnailUrl
        self.songCount = songCount
        self.duration = duration
        self.bookmarkedAt = bookmarkedAt
        self.isUploaded = isUploaded
    }
}

/// A stored playlist row.
public struct SyncPlaylist: Sendable, Hashable {
    public var id: String
    public var browseId: String?
    public var name: String
    public var thumbnailUrl: String?
    public var isEditable: Bool
    public var bookmarkedAt: Date?
    public var remoteSongCount: Int?
    public var isAutoSync: Bool

    public init(
        id: String,
        browseId: String?,
        name: String,
        thumbnailUrl: String? = nil,
        isEditable: Bool,
        bookmarkedAt: Date?,
        remoteSongCount: Int? = nil,
        isAutoSync: Bool = false
    ) {
        self.id = id
        self.browseId = browseId
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.isEditable = isEditable
        self.bookmarkedAt = bookmarkedAt
        self.remoteSongCount = remoteSongCount
        self.isAutoSync = isAutoSync
    }
}

extension SyncPlaylist {
    /// Merges fetched playlist metadata over the stored row, preserving the
    /// user's name/editability/bookmark. Used when materializing a playlist's
    /// contents (sync + detail); the liked-playlists sync keeps its own
    /// policy (name/thumbnail always refresh, bookmark defaults to now).
    public static func merging(
        existing: SyncPlaylist?,
        id: String,
        browseId: String?,
        name: String,
        remoteSongCount: Int
    ) -> SyncPlaylist {
        SyncPlaylist(
            id: id,
            browseId: browseId,
            name: existing?.name ?? name,
            isEditable: existing?.isEditable ?? false,
            bookmarkedAt: existing?.bookmarkedAt,
            remoteSongCount: remoteSongCount
        )
    }
}

/// A stored podcast row.
public struct SyncPodcast: Sendable, Hashable {
    public var id: String
    public var name: String
    public var thumbnailUrl: String?
    public var subscribedAt: Date?

    public init(id: String, name: String, thumbnailUrl: String?, subscribedAt: Date?) {
        self.id = id
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.subscribedAt = subscribedAt
    }
}

/// A playlist membership row.
public struct SyncPlaylistEntry: Sendable, Hashable {
    public var playlistId: String
    public var songId: String
    public var position: Int
    public var setVideoId: String?

    public init(playlistId: String, songId: String, position: Int, setVideoId: String?) {
        self.playlistId = playlistId
        self.songId = songId
        self.position = position
        self.setVideoId = setVideoId
    }
}

public enum MutationError: Error, LocalizedError, Sendable {
    case playlistCreationFailed
    public var errorDescription: String? { "Failed to create playlist" }
}
