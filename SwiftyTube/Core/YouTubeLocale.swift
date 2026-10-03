//
//  YouTubeLocale.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Region + language.
public struct YouTubeLocale: Sendable, Hashable, Codable {
    public let gl: String
    public let hl: String

    public init(gl: String, hl: String) {
        self.gl = gl
        self.hl = hl
    }

    public static let `default` = YouTubeLocale(gl: "US", hl: "en")
}
