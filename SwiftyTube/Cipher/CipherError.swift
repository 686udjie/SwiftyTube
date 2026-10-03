//
//  CipherError.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

public enum CipherError: Error, LocalizedError, Sendable {
    case hashNotFound
    case invalidResponse(String)
    case cacheUnavailable
    case signatureTimestampNotFound
    case functionNotFound(String)
    case jsExecutionFailed(String)
    case configNotAvailable
    case deobfuscationFailed(String)
    case nTransformFailed(String)

    public var errorDescription: String? {
        switch self {
        case .hashNotFound: return "Player hash not found in iframe_api"
        case .invalidResponse(let message): return "Invalid response: \(message)"
        case .cacheUnavailable: return "Cache directory unavailable"
        case .signatureTimestampNotFound: return "Signature timestamp not found in player.js"
        case .functionNotFound(let name): return "Cipher function not found: \(name)"
        case .jsExecutionFailed(let message): return "JS execution failed: \(message)"
        case .configNotAvailable: return "No config entry for this player hash"
        case .deobfuscationFailed(let message): return "Deobfuscation failed: \(message)"
        case .nTransformFailed(let value): return "n-param transform failed: \(value)"
        }
    }
}
