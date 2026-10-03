//
//  AccountInfo.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Signed-in account (from account menu).
public struct AccountInfo: Sendable, Hashable, Codable {
    public var name: String
    public var email: String?
    public var channelHandle: String?
    public var thumbnailUrl: String?

    public init(
        name: String,
        email: String? = nil,
        channelHandle: String? = nil,
        thumbnailUrl: String? = nil
    ) {
        self.name = name
        self.email = email
        self.channelHandle = channelHandle
        self.thumbnailUrl = thumbnailUrl
    }
}
