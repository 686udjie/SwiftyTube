//
//  IncrementalSyncService.swift
//  SwiftyTube
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation

public actor IncrementalSyncService {
    private let client: InnerTubeClient
    private let librarySync: LibrarySyncService
    private let defaults: UserDefaults

    private let lastSyncKey = "lastSyncTimestamp"
    private let syncThreshold: TimeInterval = 30 * 60 // 30 minutes

    public init(client: InnerTubeClient, librarySync: LibrarySyncService, defaults: UserDefaults = .standard) {
        self.client = client
        self.librarySync = librarySync
        self.defaults = defaults
    }

    nonisolated public var lastSyncDate: Date? {
        defaults.object(forKey: lastSyncKey) as? Date
    }

    public func checkAndSyncIfStale(
        options: LibrarySyncOptions = LibrarySyncOptions(),
        onLikesRefresh: (@Sendable () async -> Void)? = nil
    ) async {
        let lastSync = lastSyncDate ?? .distantPast
        guard Date().timeIntervalSince(lastSync) >= syncThreshold else {
            return
        }
        await forceFullSync(options: options, onLikesRefresh: onLikesRefresh)
    }

    public func forceFullSync(
        options: LibrarySyncOptions = LibrarySyncOptions(),
        onLikesRefresh: (@Sendable () async -> Void)? = nil
    ) async {
        // Verify login first
        guard (try? await client.accountMenu()) != nil else { return }

        let result = await librarySync.syncAll(options: options, onLikesRefresh: onLikesRefresh)
        guard result.completedSections > 0 else { return }
        defaults.set(Date(), forKey: lastSyncKey)
    }
}
