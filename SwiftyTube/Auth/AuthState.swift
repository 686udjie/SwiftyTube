//
//  AuthState.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Session fields for signed-in requests. Apps own storage; the lib only reads.
public struct AuthState: Sendable, Hashable, Codable {
    public var cookies: [String: String]
    public var sapisid: String?
    public var visitorData: String?
    public var dataSyncId: String?

    public init(
        cookies: [String: String] = [:],
        sapisid: String? = nil,
        visitorData: String? = nil,
        dataSyncId: String? = nil
    ) {
        self.cookies = cookies
        self.sapisid = sapisid
        self.visitorData = visitorData
        self.dataSyncId = dataSyncId
    }

    public static let guest = AuthState()
}
