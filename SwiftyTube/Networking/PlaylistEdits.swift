//
//  PlaylistEdits.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// `browse/edit_playlist` action dicts. Both apps edit playlists.
public enum PlaylistEditAction: Sendable {
    case addVideo(videoId: String, setVideoId: String? = nil)
    case removeVideo(setVideoId: String)
    case renamePlaylist(name: String)

    public var dictionary: [String: Any] {
        switch self {
        case .addVideo(let videoId, let setVideoId):
            var action: [String: Any] = [
                "action": "ACTION_ADD_VIDEO",
                "addedVideoId": videoId
            ]
            if let setVideoId {
                action["setVideoId"] = setVideoId
            }
            return action
        case .removeVideo(let setVideoId):
            return [
                "action": "ACTION_REMOVE_VIDEO",
                "setVideoId": setVideoId
            ]
        case .renamePlaylist(let name):
            return [
                "action": "ACTION_SET_PLAYLIST_NAME",
                "name": name
            ]
        }
    }

    public static func dictionaries(_ actions: [PlaylistEditAction]) -> [[String: Any]] {
        actions.map { $0.dictionary }
    }

    /// Playlist id from a `playlist/create` response (`playlistId` or nested).
    public static func extractPlaylistId(from json: [String: Any]) -> String? {
        if let playlistId = json["playlistId"] as? String { return playlistId }
        if let response = json["response"] as? [String: Any],
           let playlistId = response["playlistId"] as? String { return playlistId }
        return nil
    }
}

/// Apply → remote → rollback + rethrow.
public enum OptimisticMutation: Sendable {
    public static func attemptingRemote(
        _ remote: () async throws -> Void,
        rollback: () async -> Void
    ) async throws {
        do {
            try await remote()
        } catch {
            await rollback()
            throw error
        }
    }
}
