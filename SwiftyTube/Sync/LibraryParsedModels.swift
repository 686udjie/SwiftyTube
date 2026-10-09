//
//  LibraryParsedModels.swift
//  SwiftyTube
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation

/// A song row from a library shelf.
public struct ParsedSong: Sendable, Hashable {
    public var videoId: String
    public var title: String
    public var artists: [String]
    public var artistIds: [String]
    public var album: String?
    public var albumId: String?
    public var duration: Int
    public var thumbnailUrl: String?
    public var isLiked: Bool
    public var libraryAddToken: String?
    public var libraryRemoveToken: String?

    public init(
        videoId: String,
        title: String,
        artists: [String],
        artistIds: [String],
        album: String?,
        albumId: String?,
        duration: Int,
        thumbnailUrl: String?,
        isLiked: Bool,
        libraryAddToken: String?,
        libraryRemoveToken: String?
    ) {
        self.videoId = videoId
        self.title = title
        self.artists = artists
        self.artistIds = artistIds
        self.album = album
        self.albumId = albumId
        self.duration = duration
        self.thumbnailUrl = thumbnailUrl
        self.isLiked = isLiked
        self.libraryAddToken = libraryAddToken
        self.libraryRemoveToken = libraryRemoveToken
    }
}

/// A saved album row.
public struct ParsedAlbum: Sendable, Hashable {
    public var browseId: String
    public var title: String
    public var artist: String?
    public var thumbnailUrl: String?
    public var songCount: Int
    public var duration: Int
    public var playlistId: String?

    public init(
        browseId: String,
        title: String,
        artist: String?,
        thumbnailUrl: String?,
        songCount: Int,
        duration: Int,
        playlistId: String?
    ) {
        self.browseId = browseId
        self.title = title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.songCount = songCount
        self.duration = duration
        self.playlistId = playlistId
    }
}

/// A subscribed artist row.
public struct ParsedArtist: Sendable, Hashable {
    public var browseId: String
    public var name: String
    public var thumbnailUrl: String?
    public var isSubscribed: Bool
    public var channelId: String?

    public init(
        browseId: String,
        name: String,
        thumbnailUrl: String?,
        isSubscribed: Bool,
        channelId: String?
    ) {
        self.browseId = browseId
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.isSubscribed = isSubscribed
        self.channelId = channelId
    }
}

/// A liked playlist row.
public struct ParsedPlaylist: Sendable, Hashable {
    public var browseId: String
    public var title: String
    public var songCount: Int?
    public var thumbnailUrl: String?

    public init(browseId: String, title: String, songCount: Int?, thumbnailUrl: String?) {
        self.browseId = browseId
        self.title = title
        self.songCount = songCount
        self.thumbnailUrl = thumbnailUrl
    }
}

/// A subscribed podcast row.
public struct ParsedPodcast: Sendable, Hashable {
    public var browseId: String
    public var name: String
    public var thumbnailUrl: String?
    public var isSubscribed: Bool

    public init(browseId: String, name: String, thumbnailUrl: String?, isSubscribed: Bool) {
        self.browseId = browseId
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.isSubscribed = isSubscribed
    }
}
