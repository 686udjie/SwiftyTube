//
//  SecureStoreTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Testing

@testable import SwiftyTube

@Suite("SecureStore")
struct SecureStoreTests {
    private func uniqueStore() -> (SecureStore, String) {
        let service = "com.swiftytube.tests.\(UUID().uuidString)"
        let key = "key-\(UUID().uuidString)"
        return (SecureStore(service: service), key)
    }

    @Test("Save, load, delete round trip")
    func roundTrip() throws {
        let (store, key) = uniqueStore()
        defer { try? store.delete(for: key) }

        do {
            _ = try store.load(for: key)
            Issue.record("expected notFound")
        } catch let error as SecureStoreError {
            #expect(error == .notFound)
        }

        try store.save(Data("secret".utf8), for: key)
        #expect(try store.load(for: key) == Data("secret".utf8))

        try store.save(Data("rotated".utf8), for: key)
        #expect(try store.load(for: key) == Data("rotated".utf8))

        try store.delete(for: key)
        try store.delete(for: key)
    }

    @Test("Service name is stored")
    func service() {
        #expect(SecureStore(service: "s").service == "s")
    }
}
