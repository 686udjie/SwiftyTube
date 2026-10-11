//
//  VideoAvailability.swift
//  SwiftyTube
//
//  Created by 686udjie on 10/10/2026.
//

import Foundation

public actor VideoAvailability {
    public static let shared = VideoAvailability()

    private static let maxCachedVerdicts = 1000

    private var verdicts: [String: Bool] = [:]
    private var inflight: [String: Task<Bool, Never>] = [:]

    public init() {}

    /// Whether `videoId` has a watchable video (not an auto-generated still).
    public func hasVideo(
        videoId: String,
        rowType: String?,
        result: PlaybackResult,
        using client: InnerTubeClient
    ) async -> Bool {
        let known = rowType ?? result.musicVideoType
        if known != nil || !result.hasVideoContent {
            return PlaybackResult.hasWatchableVideo(musicVideoType: known, hasVideoContent: result.hasVideoContent)
        }
        if let cached = verdicts[videoId] {
            return cached
        }
        if let task = inflight[videoId] {
            return await task.value
        }
        let task = Task<Bool, Never> {
            await Self.fetchVerdict(videoId: videoId, result: result, using: client)
        }
        inflight[videoId] = task
        let verdict = await task.value
        inflight[videoId] = nil
        return verdict
    }

    private static func fetchVerdict(
        videoId: String,
        result: PlaybackResult,
        using client: InnerTubeClient
    ) async -> Bool {
        do {
            let response: PlayerResponse = try await client.playerResponse(videoId: videoId, client: .webRemix)
            let verdict = PlaybackResult.hasWatchableVideo(
                musicVideoType: response.videoDetails?.musicVideoType,
                hasVideoContent: result.hasVideoContent
            )
            await shared.store(videoId: videoId, verdict: verdict)
            return verdict
        } catch {
            SwiftyTubeLog.debug("VideoAvailability lookup failed for \(videoId): \(error.localizedDescription)")
            return PlaybackResult.hasWatchableVideo(musicVideoType: nil, hasVideoContent: result.hasVideoContent)
        }
    }

    private func store(videoId: String, verdict: Bool) {
        if verdicts.count >= Self.maxCachedVerdicts {
            verdicts.removeAll()
        }
        verdicts[videoId] = verdict
    }

    /// Watch-endpoint music type of a row (`MUSIC_VIDEO_TYPE_ATV` for
    /// auto-generated art-tracks), from the renderer's own endpoint first,
    /// then the title-run endpoints. Nil when the row carries none.
    public static func rowMusicVideoType(_ renderer: [String: Any]) -> String? {
        if let nav = renderer["navigationEndpoint"] as? [String: Any],
           let type = musicVideoType(in: nav) {
            return type
        }
        guard let flexColumns = renderer["flexColumns"] as? [[String: Any]],
              let first = flexColumns.first else { return nil }
        let col = (first["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])
            ?? (first["musicResponsiveListItemColumnRenderer"] as? [String: Any])
        let runs = (col?["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
        for run in runs {
            if let nav = run["navigationEndpoint"] as? [String: Any],
               let type = musicVideoType(in: nav) {
                return type
            }
        }
        return nil
    }

    private static func musicVideoType(in nav: [String: Any]) -> String? {
        ((nav["watchEndpoint"] as? [String: Any])?["watchEndpointMusicSupportedConfigs"] as? [String: Any])
            .flatMap { $0["watchEndpointMusicConfig"] as? [String: Any] }
            .flatMap { $0["musicVideoType"] as? String }
    }
}
