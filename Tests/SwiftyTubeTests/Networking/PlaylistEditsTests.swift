//
//  PlaylistEditsTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

@Suite("Playlist edits")
struct PlaylistEditsTests {
    @Test("Add action omits nil setVideoId")
    func addAction() {
        let withSet = PlaylistEditAction.addVideo(videoId: "v", setVideoId: "s").dictionary
        #expect(withSet["action"] as? String == "ACTION_ADD_VIDEO")
        #expect(withSet["addedVideoId"] as? String == "v")
        #expect(withSet["setVideoId"] as? String == "s")

        let withoutSet = PlaylistEditAction.addVideo(videoId: "v").dictionary
        #expect(withoutSet["setVideoId"] == nil)
    }

    @Test("Remove and rename actions")
    func removeAndRename() {
        let remove = PlaylistEditAction.removeVideo(setVideoId: "s").dictionary
        #expect(remove["action"] as? String == "ACTION_REMOVE_VIDEO")

        let rename = PlaylistEditAction.renamePlaylist(name: "Gym").dictionary
        #expect(rename["action"] as? String == "ACTION_SET_PLAYLIST_NAME")
        #expect(rename["name"] as? String == "Gym")

        let all = PlaylistEditAction.dictionaries([.addVideo(videoId: "v"), .removeVideo(setVideoId: "s")])
        #expect(all.count == 2)
    }

    @Test("Playlist id from either envelope")
    func extractId() {
        #expect(PlaylistEditAction.extractPlaylistId(from: ["playlistId": "PL1"]) == "PL1")
        #expect(PlaylistEditAction.extractPlaylistId(from: ["response": ["playlistId": "PL2"]]) == "PL2")
        #expect(PlaylistEditAction.extractPlaylistId(from: [:]) == nil)
    }

    @Test("Optimistic mutation passes through and rolls back")
    func optimistic() async throws {
        var rolledBack = false
        try await OptimisticMutation.attemptingRemote({}, rollback: { rolledBack = true })
        #expect(rolledBack == false)

        struct Boom: Error {}
        do {
            try await OptimisticMutation.attemptingRemote(
                { throw Boom() },
                rollback: { rolledBack = true }
            )
            Issue.record("expected throw")
        } catch is Boom {
            #expect(rolledBack == true)
        }
    }
}
