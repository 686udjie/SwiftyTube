//
//  InnerTubeClient.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

// Minimal transport actor. Returns raw JSON - apps parse
// music vs. video schemas themselves.

import Foundation

/// Shared InnerTube transport.
public actor InnerTubeClient {
    public private(set) var config: SwiftyTubeConfig
    let session: URLSession
    private let decoder: JSONDecoder

    var auth: AuthState

    public init(config: SwiftyTubeConfig, auth: AuthState = .guest) {
        self.config = config
        self.auth = auth

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeoutSeconds
        self.session = URLSession(configuration: sessionConfig)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - Auth

    public func updateAuth(_ auth: AuthState) {
        self.auth = auth
    }

    public func currentAuth() -> AuthState {
        auth
    }

    /// New default locale (and Accept-Language) for future requests.
    public func updateLocale(_ locale: YouTubeLocale) {
        config.defaultLocale = locale
        config.acceptLanguage = "en-\(locale.gl),en;q=0.9"
    }

    // MARK: - Endpoints (raw JSON, app parses)

    public func browse(
        browseId: String? = nil,
        params: String? = nil,
        continuation: String? = nil,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = ["context": contextDict(client: client, locale: locale)]
        if let browseId { body["browseId"] = browseId }
        if let params { body["params"] = params }
        if let continuation { body["continuation"] = continuation }
        let json = try await post(endpoint: "browse", body: body, client: client)
        if let responseContext = json["responseContext"] as? [String: Any],
           let visitorData = responseContext["visitorData"] as? String
        {
            auth.visitorData = visitorData
        }
        return json
    }

    public func search(
        query: String,
        params: String? = nil,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "query": query
        ]
        if let params { body["params"] = params }
        return try await post(endpoint: "search", body: body, client: client)
    }

    public func next(
        videoId: String? = nil,
        playlistId: String? = nil,
        index: Int? = nil,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = ["context": contextDict(client: client, locale: locale)]
        if let videoId { body["videoId"] = videoId }
        if let playlistId { body["playlistId"] = playlistId }
        if let index { body["index"] = index }
        return try await post(endpoint: "next", body: body, client: client)
    }

    public func player(
        videoId: String,
        playlistId: String? = nil,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil,
        options: PlayerRequestOptions = .default
    ) async throws -> [String: Any] {
        let client = client ?? config.defaultClient
        let body = makePlayerBody(
            videoId: videoId,
            playlistId: playlistId,
            client: client,
            locale: locale ?? config.defaultLocale,
            options: options
        )
        return try await post(endpoint: "player", body: body, client: client)
    }

    /// Typed `/player` decode.
    public func playerResponse<T: Decodable>(
        videoId: String,
        playlistId: String? = nil,
        client: YouTubeClient? = nil,
        locale: YouTubeLocale? = nil,
        options: PlayerRequestOptions = .default,
        as type: T.Type = T.self
    ) async throws -> T {
        let client = client ?? config.defaultClient
        let body = makePlayerBody(
            videoId: videoId,
            playlistId: playlistId,
            client: client,
            locale: locale ?? config.defaultLocale,
            options: options
        )
        let data = try await postData(endpoint: "player", body: body, client: client)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw InnerTubeError.decodingFailed
        }
    }

    // MARK: - Core POST

    /// `/player` body.
    private func makePlayerBody(
        videoId: String,
        playlistId: String?,
        client: YouTubeClient,
        locale: YouTubeLocale,
        options: PlayerRequestOptions
    ) -> [String: Any] {
        var body: [String: Any] = [
            "context": contextDict(client: client, locale: locale),
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        if !client.useMusicPlayerEndpoint {
            body["videoCheckOk"] = true
        }
        if let playlistId {
            body["playlistId"] = playlistId
        }
        if let signatureTimestamp = options.signatureTimestamp {
            var contentPlaybackContext: [String: Any] = ["signatureTimestamp": signatureTimestamp]
            if !client.useMusicPlayerEndpoint {
                contentPlaybackContext["html5Preference"] = "HTML5_PREF_WANTS"
            }
            body["playbackContext"] = ["contentPlaybackContext": contentPlaybackContext]
        }
        if let poToken = options.poToken {
            body["serviceIntegrityDimensions"] = ["poToken": poToken]
        }
        if client.isEmbedded {
            body["thirdParty"] = ["embedUrl": "https://www.youtube.com/embed/\(videoId)"]
        }
        return body
    }

    func post(
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient?
    ) async throws -> [String: Any] {
        let data = try await postData(endpoint: endpoint, body: body, client: client)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.decodingFailed
        }
        return json
    }

    func postData(
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient?
    ) async throws -> Data {
        let client = client ?? config.defaultClient
        let request = RequestBuilder.buildRequest(
            config: config,
            endpoint: endpoint,
            body: body,
            client: client,
            auth: auth
        )
        return try await RetryPolicy.innerTube.run(
            { try await Self.postOnce(request: request, session: session) },
            isRetryable: Self.isRetryable,
            onRetry: { attempt, error in
                SwiftyTubeLog.debug("Retry \(attempt + 1) for \(endpoint): \(error.localizedDescription)")
            }
        )
    }

    private nonisolated static func postOnce(request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InnerTubeError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw InnerTubeError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        return data
    }

    private nonisolated static let isRetryable: @Sendable (Error) -> Bool = { error in
        if case InnerTubeError.httpError(let code, _) = error {
            // 5xx and rate-limits are transient; 4xx (bad request, blocked) are not.
            return code >= 500 || code == 429
        }
        switch error {
        case InnerTubeError.decodingFailed, InnerTubeError.invalidResponse:
            // A 200 with an undecodable body will not recover by retrying.
            return false
        default:
            return true
        }
    }

    // MARK: - Context

    func contextDict(
        client: YouTubeClient?,
        locale: YouTubeLocale?
    ) -> [String: Any] {
        let client = client ?? config.defaultClient
        let locale = locale ?? config.defaultLocale

        var clientDict: [String: Any] = [
            "clientName": client.clientName,
            "clientVersion": client.clientVersion,
            "gl": locale.gl,
            "hl": locale.hl
        ]
        if let visitorData = auth.visitorData {
            clientDict["visitorData"] = visitorData
        }
        if client.includeUserAgentInContext {
            clientDict["userAgent"] = client.userAgent
        }
        if let osName = client.osName { clientDict["osName"] = osName }
        if let osVersion = client.osVersion { clientDict["osVersion"] = osVersion }
        if let deviceMake = client.deviceMake { clientDict["deviceMake"] = deviceMake }
        if let deviceModel = client.deviceModel { clientDict["deviceModel"] = deviceModel }
        if let androidSdkVersion = client.androidSdkVersion {
            clientDict["androidSdkVersion"] = androidSdkVersion
        }
        if let platform = client.platform { clientDict["platform"] = platform }
        if let clientScreen = client.clientScreen { clientDict["clientScreen"] = clientScreen }
        if let embedUrl = client.embedUrl {
            clientDict["embedUrl"] = embedUrl
        }

        var context: [String: Any] = [
            "client": clientDict,
            "request": ["useSsl": true]
        ]
        var user: [String: Any] = ["lockedSafetyMode": false]
        if let dataSyncId = auth.dataSyncId {
            user["onBehalfOfUser"] = dataSyncId
        }
        context["user"] = user
        return context
    }
}
