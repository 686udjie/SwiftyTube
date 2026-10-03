//
//  CipherPoTokenTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

@Suite("Cipher and PoToken")
struct CipherPoTokenTests {
    @Test("Config doc parses, bad entries skipped, duplicates rejected")
    func configParse() {
        let doc = """
        {"schemaVersion":1,"players":{
        "9c249f6f":{"sig":"Tl(48,5831,INPUT)","nClass":"W_","sts":20602},
        "badhash!":{"sig":"Tl(48,5831,INPUT)","nClass":"W_","sts":1},
        "11111111":{"sig":"evil();doBad(INPUT)","nClass":"W_","sts":1},
        "22222222":{"sig":"Tl(1,2,INPUT)","nClass":"W_","sts":0}
        }}
        """
        let configs = PlayerConfigStore.parse(text: doc)
        #expect(configs?.count == 1)
        #expect(configs?["9c249f6f"]?.sts == 20602)

        #expect(PlayerConfigStore.parse(text: "not json") == nil)
        #expect(PlayerConfigStore.parse(text: #"{"schemaVersion":2,"players":{}}"#) == nil)
        let dup = """
        {"schemaVersion":1,"players":{
        "aaaaaaaa":{"sig":"Tl(1,2,INPUT)","nClass":"W_","sts":1,"aliases":["aaaaaaaa"]}
        }}
        """
        #expect(PlayerConfigStore.parse(text: dup) == nil)
    }

    @Test("po_token.html loads from an embedding bundle")
    func bundledResources() throws {
        // Static libs can't own resources: apps embed the file, the lib finds it.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "obtainPoToken runBotGuard createPoTokenMinter".write(
            to: dir.appendingPathComponent("po_token.html"),
            atomically: true,
            encoding: .utf8
        )
        guard let bundle = Bundle(path: dir.path) else {
            Issue.record("test bundle not created")
            return
        }
        let html = PoTokenGenerator.html(bundle: bundle)
        #expect(html?.contains("obtainPoToken") == true)
        #expect(html?.contains("runBotGuard") == true)
        #expect(html?.contains("createPoTokenMinter") == true)
    }

    @Test("Signature timestamp extraction")
    func signatureTimestamp() throws {
        let js = #"var x={signatureTimestamp:18976,sig:sig};"#
        #expect(try PlayerJsFetcher.extractSignatureTimestamp(from: js) == 18976)
    }

    @Test("Heuristic cipher extraction finds split/join function")
    func heuristicExtraction() async throws {
        // Minified assignment form, as found in real player.js.
        let js = """
        var other=function(a){return a+1;};
        var dD=function(s){var x=s.split("").reverse();return x.join("");};
        """
        let extractor = FunctionNameExtractor()
        let found = try await extractor.extract(from: js)
        #expect(found.sigJs.contains("split"))
        #expect(found.sigJs.contains("join"))
    }

    @Test("HTML patch exports cipher entry points")
    func htmlPatch() {
        let patched = CipherHTMLBuilder.patchPlayerJs(
            playerJs: "code;})(_yt_player);",
            sigConfig: "Ab(12,34,INPUT)",
            nClass: "W_",
            nJsExpression: nil,
            playerHash: "abc"
        )
        #expect(patched.contains("window._cipherSigFunc"))
        #expect(patched.contains("window._buildSignedUrl"))
    }

    @Test("BotGuard parsing helpers")
    func botGuardParsing() throws {
        #expect(BotGuardService.descramble("Bwg.") == "hi")
        let (u8, expires) = try BotGuardService.parseIntegrityToken(#"["QUJD",3600]"#)
        #expect(u8 == "new Uint8Array([65,66,67])")
        #expect(expires == 3600)

        let challenge = try BotGuardService.parseChallenge(
            #"[["m",["script"],"x","h","prog","g",7,8],0]"#
        )
        #expect(challenge.program == "prog")
        #expect(challenge.globalName == "g")
        #expect(challenge.interpreterJavascript == "script")
    }

    @Test("JS escaping")
    func jsEscaping() {
        #expect(JSEscaping.escape("a\"b\\c") == "a\\\"b\\\\c")
    }

    @Test("Live providers wiring exists")
    func providersWiring() {
        let providers = StreamResolveProviders.live
        #expect(providers.signatureTimestamp != nil)
        #expect(providers.cipherURL != nil)
        #expect(providers.playerJs != nil)
        #expect(providers.onStreamRejection != nil)
    }
}
