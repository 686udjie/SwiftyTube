//
//  RequestBuilder.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// URLRequests from config + client + auth. No app singletons.
enum RequestBuilder: Sendable {
    static func buildRequest(
        config: SwiftyTubeConfig,
        endpoint: String,
        body: [String: Any],
        client: YouTubeClient,
        auth: AuthState
    ) -> URLRequest {
        let url = config.service.baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue("\(client.clientId)", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(config.service.origin, forHTTPHeaderField: "X-Origin")
        request.setValue(config.service.origin + "/", forHTTPHeaderField: "Referer")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(config.acceptLanguage, forHTTPHeaderField: "Accept-Language")

        if let visitorData = auth.visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        if client.loginSupported {
            if !auth.cookies.isEmpty {
                let cookieString = auth.cookies
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "; ")
                request.setValue(cookieString, forHTTPHeaderField: "Cookie")
            }
            if let sapisid = auth.sapisid {
                request.setValue(
                    SAPISIDAuth.authorizationHeader(sapisid: sapisid, origin: config.service.origin),
                    forHTTPHeaderField: "Authorization"
                )
            }
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func buildPlaybackTrackingRequest(
        config: SwiftyTubeConfig,
        trackingUrl: String,
        client: YouTubeClient,
        auth: AuthState,
        playlistId: String? = nil
    ) -> URLRequest? {
        guard var components = URLComponents(string: trackingUrl) else { return nil }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "c", value: client.clientName))
        queryItems.append(URLQueryItem(name: "cpn", value: Self.randomCpn()))
        queryItems.append(URLQueryItem(name: "ver", value: "2"))
        if let playlistId {
            queryItems.append(URLQueryItem(name: "list", value: playlistId))
            queryItems.append(URLQueryItem(
                name: "referrer",
                value: "\(config.service.origin)/playlist?list=\(playlistId)"
            ))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue("\(client.clientId)", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(config.service.origin, forHTTPHeaderField: "X-Origin")
        request.setValue(config.service.origin + "/", forHTTPHeaderField: "Referer")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")

        if let visitorData = auth.visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        if client.loginSupported {
            if !auth.cookies.isEmpty {
                let cookieString = auth.cookies
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "; ")
                request.setValue(cookieString, forHTTPHeaderField: "Cookie")
            }
            if let sapisid = auth.sapisid {
                request.setValue(
                    SAPISIDAuth.authorizationHeader(sapisid: sapisid, origin: config.service.origin),
                    forHTTPHeaderField: "Authorization"
                )
            }
        }

        return request
    }

    private static let cpnChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"

    private static func randomCpn() -> String {
        (0 ..< 16).map { _ in cpnChars.randomElement()! }.map(String.init).joined()
    }
}
