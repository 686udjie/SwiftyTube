//
//  SAPISIDAuthTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Testing

@testable import SwiftyTube

@Suite("SAPISIDAuth")
struct SAPISIDAuthTests {
    @Test("Header has SAPISIDHASH timestamp_hash shape")
    func shape() {
        let header = SAPISIDAuth.authorizationHeader(
            sapisid: "test-sapisid",
            origin: "https://www.youtube.com"
        )
        #expect(header.hasPrefix("SAPISIDHASH "))
        let payload = header.dropFirst("SAPISIDHASH ".count)
        let parts = payload.split(separator: "_")
        #expect(parts.count == 2)
        // SHA1 hex digest
        #expect(parts[1].count == 40)
        #expect(Int(parts[0]) != nil)
    }

    @Test("Different origins give different hashes")
    func originMatters() {
        let a = SAPISIDAuth.authorizationHeader(sapisid: "x", origin: "https://www.youtube.com")
        let b = SAPISIDAuth.authorizationHeader(sapisid: "x", origin: "https://music.youtube.com")
        #expect(a != b)
    }
}
