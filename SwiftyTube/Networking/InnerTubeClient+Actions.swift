//
//  InnerTubeClient+Actions.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

// Account, library and queue endpoints. Parsing stays in apps.
public extension InnerTubeClient {
    // MARK: - Auth state

    /// Loads persisted session fields from the app's store.
    func loadState(from store: any AuthStateProvider) async {
        auth = AuthState(
            cookies: await store.cookies(),
            sapisid: await store.sapisid(),
            visitorData: await store.visitorData(),
            dataSyncId: await store.dataSyncId()
        )
    }

    /// Ensures visitorData is set, fetching it via the home tab if needed.
    func ensureVisitorData(
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws {
        if auth.visitorData != nil { return }
        let homeId = config.service == .music ? "FEmusic_home" : "FEwhat_to_watch"
        _ = try await browse(browseId: homeId, client: client, locale: locale)
    }

    /// Duration only, via the iOS client.
    func fetchDuration(videoId: String) async throws -> Int {
        let response: PlayerResponse = try await playerResponse(videoId: videoId, client: .iOS)
        guard let lengthSeconds = response.videoDetails?.lengthSeconds,
              let duration = Int(lengthSeconds) else {
            throw InnerTubeError.decodingFailed
        }
        DurationCache.set(videoId, duration)
        return duration
    }

    /// Cached duration, else fetch. Nil while another task fetches.
    func resolveDuration(videoId: String) async -> Int? {
        if let cached = DurationCache.get(videoId), cached > 0 {
            return cached
        }
        guard !DurationCache.isPending(videoId) else { return nil }
        DurationCache.markPending(videoId)
        do {
            return try await fetchDuration(videoId: videoId)
        } catch {
            DurationCache.clearPending(videoId)
            return nil
        }
    }

    // MARK: - Pagination

    /// All pages via continuations (stops on repeats/cap).
    func paginate<T>(
        browseId: String,
        params: String? = nil,
        maxPages: Int = 50,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil,
        parse: @escaping ([String: Any]) -> [T],
        continuation: @escaping ([String: Any]) -> String?
    ) async throws -> [T] {
        var allItems: [T] = []
        var token: String?
        var seenTokens = Set<String>()
        var pages = 0
        repeat {
            let json = try await browse(
                browseId: browseId,
                params: params,
                continuation: token,
                client: client,
                locale: locale
            )
            allItems.append(contentsOf: parse(json))
            token = continuation(json)
            pages += 1
            if let token, !seenTokens.insert(token).inserted {
                SwiftyTubeLog.error("paginate \(browseId): repeated continuation token, stopping")
                break
            }
            if pages >= maxPages {
                SwiftyTubeLog.error("paginate \(browseId): hit \(maxPages)-page cap, stopping")
                break
            }
        } while token != nil
        return allItems
    }

    // MARK: - Account

    /// Account menu (verifies signed-in state).
    func accountMenu(
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        let body = ["context": contextDict(client: client, locale: locale)]
        return try await post(endpoint: "account/account_menu", body: body, client: client)
    }

    /// Fetches account info (name, email, profile picture).
    func accountInfo(
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> AccountInfo {
        let json = try await accountMenu(client: client, locale: locale)
        return Self.extractAccountInfo(from: json)
    }

    private static func extractAccountInfo(from json: [String: Any]) -> AccountInfo {
        guard let actions = json["actions"] as? [[String: Any]],
              let first = actions.first,
              let openPopup = first["openPopupAction"] as? [String: Any],
              let popup = openPopup["popup"] as? [String: Any],
              let multiPageMenu = popup["multiPageMenuRenderer"] as? [String: Any],
              let header = multiPageMenu["header"] as? [String: Any],
              let activeAccount = header["activeAccountHeaderRenderer"] as? [String: Any] else {
            return AccountInfo(name: "Guest")
        }
        let name = InnerTubeJSON.runsText(activeAccount["accountName"] as? [String: Any]) ?? "Guest"
        let email = InnerTubeJSON.runsText(activeAccount["email"] as? [String: Any])
        let handle = InnerTubeJSON.runsText(activeAccount["channelHandle"] as? [String: Any])
        let thumbnails = (activeAccount["accountPhoto"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        return AccountInfo(
            name: name,
            email: email,
            channelHandle: handle,
            thumbnailUrl: InnerTubeJSON.lastThumbnailURL(thumbnails)
        )
    }

    // MARK: - Likes

    func like(
        videoId: String,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        let body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "target": ["videoId": videoId]
        ]
        return try await post(endpoint: "like/like", body: body, client: client)
    }

    func unlike(
        videoId: String,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        let body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "target": ["videoId": videoId]
        ]
        return try await post(endpoint: "like/removelike", body: body, client: client)
    }

    // MARK: - Library mutations

    /// Library add/remove tokens.
    func feedback(
        tokens: [String],
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        let body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "feedbackTokens": tokens
        ]
        return try await post(endpoint: "feedback", body: body, client: client)
    }

    /// Add, remove, or reorder playlist videos.
    func editPlaylist(
        playlistId: String,
        actions: [[String: Any]],
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        let body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "playlistId": playlistId,
            "actions": actions
        ]
        return try await post(endpoint: "browse/edit_playlist", body: body, client: client)
    }

    /// Create a new playlist.
    func createPlaylist(
        title: String,
        description: String? = nil,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "title": title
        ]
        if let description { body["description"] = description }
        return try await post(endpoint: "playlist/create", body: body, client: client)
    }

    /// Delete a playlist.
    func deletePlaylist(
        playlistId: String,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        let body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "playlistId": playlistId
        ]
        return try await post(endpoint: "playlist/delete", body: body, client: client)
    }

    // MARK: - Subscriptions

    func subscribe(
        channelId: String,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        let body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "channelIds": [channelId]
        ]
        return try await post(endpoint: "subscription/subscribe", body: body, client: client)
    }

    func unsubscribe(
        channelId: String,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        let body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "channelIds": [channelId]
        ]
        return try await post(endpoint: "subscription/unsubscribe", body: body, client: client)
    }

    // MARK: - Playback tracking

    func registerPlayback(
        trackingUrl: String,
        playlistId: String? = nil,
        client: YouTubeClient? = nil
    ) async throws {
        let client = client ?? config.defaultClient
        guard let request = RequestBuilder.buildPlaybackTrackingRequest(
            config: config,
            trackingUrl: trackingUrl,
            client: client,
            auth: auth,
            playlistId: playlistId
        ) else {
            SwiftyTubeLog.error("Failed to build playback tracking request")
            throw InnerTubeError.invalidResponse
        }
        let (data, http) = try await HttpClient.data(for: request, session: session)
        guard (200 ... 299).contains(http.statusCode) else {
            SwiftyTubeLog.error("Playback tracking HTTP \(http.statusCode)")
            throw InnerTubeError.httpError(statusCode: http.statusCode, data: data)
        }
        SwiftyTubeLog.debug("Playback registered - status=\(http.statusCode) bytes=\(data.count)")
    }
}
