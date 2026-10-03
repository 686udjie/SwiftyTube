//
//  InnerTubeDecode.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Nil-safe path walking for InnerTube JSON.
public enum InnerTubeDecode: Sendable {
    /// Walks ["a", "b"] paths. No array indexing - use `array(at:)`.
    public static func value(at path: [String], in dict: [String: Any]) -> Any? {
        var current: Any? = dict
        for key in path {
            guard let nested = current as? [String: Any] else { return nil }
            current = nested[key]
        }
        return current
    }

    public static func dict(at path: [String], in dict: [String: Any]) -> [String: Any]? {
        value(at: path, in: dict) as? [String: Any]
    }

    public static func array(at path: [String], in dict: [String: Any]) -> [[String: Any]]? {
        value(at: path, in: dict) as? [[String: Any]]
    }

    public static func string(at path: [String], in dict: [String: Any]) -> String? {
        value(at: path, in: dict) as? String
    }

    /// continuations[0].nextContinuationData token.
    public static func continuationToken(in dict: [String: Any]?) -> String? {
        guard let continuations = dict?["continuations"] as? [[String: Any]],
              let first = continuations.first,
              let next = first["nextContinuationData"] as? [String: Any],
              let token = next["continuation"] as? String else { return nil }
        return token
    }

    /// `lengthSeconds`-style fields arrive as either String or Int.
    public static func intFromStringOrInt(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    /// Runs, simpleText, text, or a bare string.
    public static func runsTextTolerant(_ dict: Any?) -> String? {
        if let string = dict as? String { return string }
        guard let nested = dict as? [String: Any] else { return nil }
        if let runs = nested["runs"] as? [[String: Any]] {
            // Join all runs - some titles split across styled runs.
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            if !joined.isEmpty { return joined }
        }
        // Fallbacks YouTube Music sometimes uses instead of runs.
        if let simple = nested["simpleText"] as? String, !simple.isEmpty { return simple }
        if let text = nested["text"] as? String, !text.isEmpty { return text }
        return nil
    }

    /// Largest thumbnail in any known envelope.
    public static func thumbnailURLTolerant(_ dict: [String: Any]?) -> String? {
        guard let dict else { return nil }
        // musicThumbnailRenderer.thumbnail.thumbnails
        if let thumb = dict["thumbnail"] as? [String: Any],
           let music = thumb["musicThumbnailRenderer"] as? [String: Any],
           let inner = music["thumbnail"] as? [String: Any],
           let list = inner["thumbnails"] as? [[String: Any]],
           let url = list.last?["url"] as? String { return url }
        // thumbnail.thumbnails
        if let thumb = dict["thumbnail"] as? [String: Any],
           let list = thumb["thumbnails"] as? [[String: Any]],
           let url = list.last?["url"] as? String { return url }
        // bare thumbnails
        if let list = dict["thumbnails"] as? [[String: Any]],
           let url = list.last?["url"] as? String { return url }
        // croppedSquareThumbnail
        if let cropped = dict["croppedSquareThumbnail"] as? [String: Any],
           let list = cropped["thumbnails"] as? [[String: Any]],
           let url = list.last?["url"] as? String { return url }
        return nil
    }

    /// One-line diagnostics for unexpected shapes.
    public static func warnOnce(_ message: String) {
        SwiftyTubeLog.notice(message)
    }
}
