//
//  HttpClient.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// URLSession helpers returning data + HTTP response.
public enum HttpClient: Sendable {
    /// Data + response. No status check.
    public static func data(
        for request: URLRequest,
        session: URLSession = .shared
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HttpError.notHTTPResponse
        }
        return (data, http)
    }

    /// Performs a GET for `url`. See `data(for:)`.
    public static func data(
        from url: URL,
        session: URLSession = .shared
    ) async throws -> (Data, HTTPURLResponse) {
        try await data(for: URLRequest(url: url), session: session)
    }

    /// Data + response, throwing on non-2xx.
    public static func validatedData(
        for request: URLRequest,
        session: URLSession = .shared
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, http) = try await data(for: request, session: session)
        guard (200 ... 299).contains(http.statusCode) else {
            throw HttpError.status(http.statusCode, data)
        }
        return (data, http)
    }
}

public enum HttpError: Error, Sendable {
    case notHTTPResponse
    case status(Int, Data)
}
