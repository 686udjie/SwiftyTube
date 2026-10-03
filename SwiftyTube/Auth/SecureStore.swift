//
//  SecureStore.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import Security

/// Generic-password Keychain wrapper. Throwing; callers map errors.
public struct SecureStore: Sendable {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func save(_ data: Data, for key: String) throws {
        var query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStoreError.unhandled(status)
        }
    }

    public func load(for key: String) throws -> Data {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw status == errSecItemNotFound ? SecureStoreError.notFound : SecureStoreError.unhandled(status)
        }
        return data
    }

    public func delete(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unhandled(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

public enum SecureStoreError: Error, Sendable, Equatable {
    case notFound
    case unhandled(OSStatus)
}
