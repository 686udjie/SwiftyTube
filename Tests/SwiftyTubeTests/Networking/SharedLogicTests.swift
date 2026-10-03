//
//  SharedLogicTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

@Suite("Shared logic")
struct SharedLogicTests {
    @Test("Continuation token from continuations array")
    func continuationToken() {
        let shelf: [String: Any] = [
            "continuations": [["nextContinuationData": ["continuation": "tok123"]]]
        ]
        #expect(InnerTubeDecode.continuationToken(in: shelf) == "tok123")
        #expect(InnerTubeDecode.continuationToken(in: nil) == nil)
        #expect(InnerTubeDecode.continuationToken(in: [:]) == nil)
        #expect(InnerTubeDecode.continuationToken(in: ["continuations": []]) == nil)
        #expect(InnerTubeDecode.continuationToken(
            in: ["continuations": [["other": 1]]]
        ) == nil)
    }

    @Test("Session import parses and prefers secure SAPISID")
    func sessionImport() throws {
        let auth = try SessionImporter.importSession(
            from: "SID=a; SAPISID=old; __Secure-3PSAPISID=new; visitor_data=v",
            dataSyncId: "d"
        )
        #expect(auth.cookies["SID"] == "a")
        #expect(auth.sapisid == "new")
        #expect(auth.visitorData == "v")
        #expect(auth.dataSyncId == "d")

        let legacy = try SessionImporter.importSession(from: "SAPISID=old")
        #expect(legacy.sapisid == "old")
        #expect(legacy.visitorData == nil)

        #expect(throws: SessionImportError.self) {
            try SessionImporter.importSession(from: "")
        }
        #expect(SessionImporter.extractSAPISID(from: [:]) == nil)
        #expect(SessionImporter.extractVisitorData(from: [:]) == nil)
    }

    @Test("resolveDuration serves cache without network")
    func resolveDurationCached() async {
        DurationCache.set("cached-dur", 321)
        let client = InnerTubeClient(config: .youtube)
        #expect(await client.resolveDuration(videoId: "cached-dur") == 321)
    }

    @Test("resolveDuration returns nil while pending")
    func resolveDurationPending() async {
        DurationCache.markPending("pending-dur")
        let client = InnerTubeClient(config: .youtube)
        #expect(await client.resolveDuration(videoId: "pending-dur") == nil)
        DurationCache.clearPending("pending-dur")
    }
}
