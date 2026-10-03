//
//  CookieParser.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Splits a raw `Set-Cookie`-style string into name→value pairs.
public enum CookieParser: Sendable {
    public static func parse(_ cookieString: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = cookieString.split(separator: ";")
        for pair in pairs {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                result[String(parts[0])] = String(parts[1])
            }
        }
        return result
    }
}
