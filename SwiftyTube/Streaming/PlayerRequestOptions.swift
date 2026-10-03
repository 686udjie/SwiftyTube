//
//  PlayerRequestOptions.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Playback-specific request knobs for `/player` calls.
public struct PlayerRequestOptions: Sendable, Hashable {
    /// Player.js signature timestamp, required by web clients.
    public var signatureTimestamp: Int?
    /// PoToken for web clients (`serviceIntegrityDimensions`).
    public var poToken: String?

    public init(signatureTimestamp: Int? = nil, poToken: String? = nil) {
        self.signatureTimestamp = signatureTimestamp
        self.poToken = poToken
    }

    public static let `default` = PlayerRequestOptions()
}
