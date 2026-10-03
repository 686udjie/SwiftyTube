//
//  StreamError.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Stream resolution errors.
public enum StreamError: Error, LocalizedError, Sendable {
    case unplayable(reason: String)
    case noStreams
    case noSuitableFormat
    case noStreamUrl
    case validationFailed(String)
    case allClientsFailed

    public var errorDescription: String? {
        switch self {
        case .unplayable(let reason):
            return "Not playable: \(reason)"
        case .noStreams:
            return "No streaming data in response"
        case .noSuitableFormat:
            return "No suitable format found"
        case .noStreamUrl:
            return "Format has no direct stream URL and no cipher data"
        case .validationFailed(let client):
            return "\(client) stream URL failed Range validation"
        case .allClientsFailed:
            return "All clients failed to resolve a valid stream URL"
        }
    }
}
