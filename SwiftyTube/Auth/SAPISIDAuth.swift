//
//  SAPISIDAuth.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import CryptoKit
import Foundation

/// SAPISIDHASH auth header.
public enum SAPISIDAuth: Sendable {
    public static func authorizationHeader(sapisid: String, origin: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let input = "\(timestamp) \(sapisid) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(timestamp)_\(hash)"
    }
}
