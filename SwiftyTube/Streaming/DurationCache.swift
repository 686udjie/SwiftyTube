//
//  DurationCache.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

public extension Notification.Name {
    /// Posted on the main queue whenever a duration is stored.
    static let durationDidUpdate = Notification.Name("SwiftyTubeDurationDidUpdate")
}

/// Thread-safe video durations with in-flight marking.
public enum DurationCache: Sendable {
    private static var cache: [String: Int] = [:]
    private static var pending: Set<String> = []
    private static let lock = NSLock()

    public static func isPending(_ videoId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pending.contains(videoId)
    }

    public static func get(_ videoId: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return cache[videoId]
    }

    public static func set(_ videoId: String, _ duration: Int) {
        lock.lock()
        cache[videoId] = duration
        pending.remove(videoId)
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .durationDidUpdate,
                object: nil,
                userInfo: ["videoId": videoId]
            )
        }
    }

    public static func markPending(_ videoId: String) {
        lock.lock(); defer { lock.unlock() }
        pending.insert(videoId)
    }

    public static func clearPending(_ videoId: String) {
        lock.lock(); defer { lock.unlock() }
        pending.remove(videoId)
    }
}
