//
//  CipherCoverageTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

@Suite("Cipher coverage")
struct CipherCoverageTests {
    @Test("File-based HTML references the hashed player file")
    func fileBasedHTML() {
        let html = CipherHTMLBuilder.buildFileBasedHTML(playerHash: "deadbeef")
        #expect(html.contains("base_deadbeef.js"))
        #expect(html.contains("ready"))
        #expect(html.contains("transformN"))
    }

    @Test("Inline HTML embeds the player source")
    func inlineHTML() {
        let html = CipherHTMLBuilder.buildHTML(
            playerJs: "var player = 1;",
            sigConfig: nil,
            nClass: nil,
            nJsExpression: nil,
            playerHash: nil
        )
        #expect(html.contains("var player = 1;"))
        #expect(html.contains("discoverAndInit"))
    }

    @Test("Extractor timestamp helper")
    func extractorTimestamp() async {
        let extractor = FunctionNameExtractor()
        let found = await extractor.extractSignatureTimestamp(from: "x signatureTimestamp: 12345 y")
        #expect(found == 12345)
        let missing = await extractor.extractSignatureTimestamp(from: "no timestamp here")
        #expect(missing == nil)
    }

    @Test("Fetcher timestamp throws when absent")
    func fetcherTimestampThrows() {
        #expect(throws: CipherError.self) {
            try PlayerJsFetcher.extractSignatureTimestamp(from: "nothing here")
        }
    }

    @Test("BotGuard base64 edge cases")
    func botGuardEdges() {
        #expect(BotGuardService.base64ToU8("!!!") == "new Uint8Array([])")
        #expect(BotGuardService.descramble("!!!") == "!!!")
    }

}
