//
//  BotGuardService.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

public actor BotGuardService {
    public static let shared = BotGuardService()

    private let apiKey = "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw"
    private let requestKey = "O43z0dpjhgX20SCx4KAo"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.3"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func createChallenge() async throws -> BotGuardChallenge {
        let url = URL(string: "https://www.youtube.com/api/jnn/v1/Create")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
        // Body: JSON array with requestKey.
        request.httpBody = try JSONSerialization.data(withJSONObject: [requestKey])

        let data: Data
        do {
            (data, _) = try await HttpClient.validatedData(for: request, session: session)
        } catch is HttpError {
            throw BotGuardError.createFailed
        }

        guard let body = String(data: data, encoding: .utf8) else {
            throw BotGuardError.invalidResponse
        }

        return try Self.parseChallenge(body)
    }

    public func generateIT(botguardResponse: String) async throws -> (integrityToken: String, expiresIn: Int) {
        let url = URL(string: "https://www.youtube.com/api/jnn/v1/GenerateIT")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
        // Body: JSON array [requestKey, botguardResponse].
        request.httpBody = try JSONSerialization.data(withJSONObject: [requestKey, botguardResponse])

        let data: Data
        do {
            (data, _) = try await HttpClient.validatedData(for: request, session: session)
        } catch is HttpError {
            throw BotGuardError.generateITFailed
        }

        guard let body = String(data: data, encoding: .utf8) else {
            throw BotGuardError.invalidResponse
        }

        return try Self.parseIntegrityToken(body)
    }

    // MARK: - Challenge Parsing

    /// Parses the raw Create response into challenge data for the WebView.
    static func parseChallenge(_ raw: String) throws -> BotGuardChallenge {
        guard let data = raw.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1 else {
            throw BotGuardError.invalidResponse
        }

        // The challenge data is either at [0] or descrambled from [1].
        let challengeArray: [Any]
        if json.count > 1, let scrambled = json[1] as? String {
            let descrambled = descramble(scrambled)
            guard let descrambledData = descrambled.data(using: .utf8),
                  let arr = try JSONSerialization.jsonObject(with: descrambledData) as? [Any] else {
                throw BotGuardError.descrambleFailed
            }
            challengeArray = arr
        } else if let arr = json[0] as? [Any] {
            challengeArray = arr
        } else {
            throw BotGuardError.invalidResponse
        }

        guard challengeArray.count >= 8,
              let messageId = challengeArray[0] as? String,
              let interpreterHash = challengeArray[3] as? String,
              let program = challengeArray[4] as? String,
              let globalName = challengeArray[5] as? String else {
            throw BotGuardError.invalidResponse
        }

        // Extract interpreter JS from element [1] (may be nested).
        var interpreterJs: String?
        if challengeArray.count > 1, let scriptArr = challengeArray[1] as? [Any] {
            for item in scriptArr {
                if let script = item as? String {
                    interpreterJs = script
                    break
                }
            }
        }

        return BotGuardChallenge(
            program: program,
            messageId: messageId,
            interpreterHash: interpreterHash,
            globalName: globalName,
            interpreterJavascript: interpreterJs
        )
    }

    /// Parses the GenerateIT response (`[base64IntegrityToken, expirationSeconds]`).
    static func parseIntegrityToken(_ raw: String) throws -> (String, Int) {
        guard let data = raw.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 2,
              let tokenB64 = json[0] as? String,
              let expiresIn = json[1] as? Int else {
            throw BotGuardError.invalidResponse
        }

        // Convert base64 to Uint8Array JS representation.
        let u8 = base64ToU8(tokenB64)
        return (u8, expiresIn)
    }

    /// Converts a base64 token to a JS Uint8Array string representation.
    static func base64ToU8(_ base64: String) -> String {
        let fixed = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: fixed) else {
            return "new Uint8Array([])"
        }
        let bytes = data.map { String($0) }.joined(separator: ",")
        return "new Uint8Array([\(bytes)])"
    }

    /// Descrambles challenge data: base64 decode + add 97 to each byte.
    static func descramble(_ scrambled: String) -> String {
        let fixed = scrambled
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: ".", with: "=")
        guard let data = Data(base64Encoded: fixed) else { return scrambled }
        let bytes = data.map { UInt8((Int($0) + 97) & 0xFF) }
        return String(data: Data(bytes), encoding: .utf8) ?? scrambled
    }
}

public struct BotGuardChallenge: Sendable {
    public let program: String
    public let messageId: String?
    public let interpreterHash: String?
    public let globalName: String?
    public let interpreterJavascript: String?

    public init(
        program: String,
        messageId: String?,
        interpreterHash: String?,
        globalName: String?,
        interpreterJavascript: String?
    ) {
        self.program = program
        self.messageId = messageId
        self.interpreterHash = interpreterHash
        self.globalName = globalName
        self.interpreterJavascript = interpreterJavascript
    }
}

public enum BotGuardError: Error, LocalizedError, Sendable {
    case createFailed
    case generateITFailed
    case invalidResponse
    case descrambleFailed

    public var errorDescription: String? {
        switch self {
        case .createFailed: return "BotGuard Create API call failed"
        case .generateITFailed: return "BotGuard GenerateIT API call failed"
        case .invalidResponse: return "Invalid BotGuard API response"
        case .descrambleFailed: return "Failed to descramble BotGuard program"
        }
    }
}
