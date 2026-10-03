//
//  InnerTubeJSON.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Tolerant readers for browse JSON (runs text, thumbnails).
public enum InnerTubeJSON: Sendable {
    /// Joined run texts, else simpleText/text.
    public static func runsText(_ dict: [String: Any]?) -> String? {
        guard let dict else { return nil }
        if let runs = dict["runs"] as? [[String: Any]], !runs.isEmpty {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            if !joined.isEmpty { return joined }
        }
        return InnerTubeDecode.runsTextTolerant(dict)
    }

    /// All non-blank run texts, dropping `" • "` separators.
    public static func runsTexts(_ dict: [String: Any]?) -> [String] {
        guard let runs = dict?["runs"] as? [[String: Any]] else { return [] }
        return runs.compactMap { $0["text"] as? String }
            .filter { $0 != " • " && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Raw runs array (empty when absent).
    public static func rawRuns(_ dict: [String: Any]?) -> [[String: Any]] {
        guard let runs = dict?["runs"] as? [[String: Any]] else { return [] }
        return runs
    }

    /// Last URL of a `thumbnails` array (largest variant).
    public static func lastThumbnailURL(_ thumbnails: [[String: Any]]?) -> String? {
        guard let last = thumbnails?.last,
              let url = last["url"] as? String else { return nil }
        return url
    }

    /// Last URL of `{thumbnail: {thumbnails: [...]}}`.
    public static func nestedThumbnailURL(_ dict: [String: Any]?) -> String? {
        lastThumbnailURL((dict?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])
    }

    /// Largest thumbnail in any known envelope.
    public static func musicThumbnailURL(_ dict: [String: Any]) -> String? {
        if let url = InnerTubeDecode.thumbnailURLTolerant(dict) {
            return url
        }
        InnerTubeDecode.warnOnce("musicThumbnailURL: unknown thumbnail envelope keys=\(dict.keys.sorted())")
        return nil
    }
}
