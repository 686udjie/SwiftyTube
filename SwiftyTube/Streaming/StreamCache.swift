//
//  StreamCache.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Stream URLs with TTL expiry.
public actor StreamCache {
    public static let shared = StreamCache()

    private var cache: [String: Entry] = [:]

    private struct Entry {
        let result: PlaybackResult
        let expiresAt: Date
    }

    public init() {}

    public func get(videoId: String) -> PlaybackResult? {
        guard let entry = cache[videoId], entry.expiresAt > Date() else {
            cache.removeValue(forKey: videoId)
            return nil
        }
        return entry.result
    }

    public func getExpired(videoId: String) -> PlaybackResult? {
        cache[videoId]?.result
    }

    public func set(videoId: String, result: PlaybackResult) {
        let ttl = result.expiresInSeconds > 60 ? result.expiresInSeconds : 5 * 3600
        let entry = Entry(result: result, expiresAt: Date().addingTimeInterval(TimeInterval(ttl)))
        cache[videoId] = entry
        SwiftyTubeLog.debug("Cached videoId=\(videoId) expires in \(ttl)s")
    }

    public func remove(videoId: String) {
        cache.removeValue(forKey: videoId)
    }

    public func clear() {
        cache.removeAll()
    }
}
