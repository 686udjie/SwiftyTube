//
//  AuthStateProvider.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Session source for `loadState`. Not `Sendable` (app stores vary).
public protocol AuthStateProvider {
    func cookies() async -> [String: String]
    func sapisid() async -> String?
    func visitorData() async -> String?
    func dataSyncId() async -> String?
}
