//
//  InnerTubeError.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

public enum InnerTubeError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, _):
            return "HTTP \(statusCode)"
        case .decodingFailed:
            return "Failed to decode response JSON"
        }
    }
}
