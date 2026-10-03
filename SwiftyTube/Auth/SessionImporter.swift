//
//  SessionImporter.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

public enum SessionImportError: Error, LocalizedError, Sendable {
    case invalidCookie
    case sapisidNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidCookie:
            return "Cookie string is empty or invalid"
        case .sapisidNotFound:
            return "Both SAPISID and __Secure-3PSAPISID missing from cookies"
        }
    }
}

/// Cookie string → sign-in state. Lenient: only empty input throws.
public enum SessionImporter: Sendable {
    public static func importSession(
        from cookieString: String,
        dataSyncId: String? = nil
    ) throws -> AuthState {
        guard !cookieString.isEmpty else {
            throw SessionImportError.invalidCookie
        }
        let cookies = CookieParser.parse(cookieString)
        return AuthState(
            cookies: cookies,
            sapisid: extractSAPISID(from: cookies),
            visitorData: extractVisitorData(from: cookies),
            dataSyncId: dataSyncId
        )
    }

    /// Prefers the `__Secure-3PSAPISID` cookie over legacy `SAPISID`.
    public static func extractSAPISID(from cookies: [String: String]) -> String? {
        if let sapisid = cookies["__Secure-3PSAPISID"] {
            return sapisid
        }
        return cookies["SAPISID"]
    }

    /// YouTube sets visitor data as a plain cookie; reuse it as the header value.
    public static func extractVisitorData(from cookies: [String: String]) -> String? {
        cookies["visitor_data"]
    }
}
