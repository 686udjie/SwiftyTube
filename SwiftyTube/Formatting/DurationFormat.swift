//
//  DurationFormat.swift
//  SwiftyTube
//
//  Created by 686udjie on 10/10/2026.
//

import Foundation

/// Duration parsing and formatting shared by parsers and apps.
public enum DurationFormat: Sendable {
    /// Parses "m:ss" / "h:mm:ss" clock strings ("." and "," tolerated as
    /// separators); nil when unparseable.
    public static func parseClock(_ text: String) -> Int? {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ":.,")).compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// "m:ss" for playback positions. Never empty; clamps negatives and
    /// non-finite values to "0:00".
    public static func playbackTime(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let total = max(Int(t), 0)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// Parses spoken durations like "1 hr 23 mins", "45 mins" or "2 hours".
    public static func parseSpoken(_ text: String) -> Int? {
        let lower = text.lowercased()
        var total = 0
        var found = false
        // Matches "<number> <unit>" pairs; units cover hr/hour/h, min/m, sec/s.
        let pattern = "(\\d+)\\s*(hours?|hrs?|\\bh\\b|minutes?|mins?|\\bm\\b|seconds?|secs?|\\bs\\b)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        for match in regex.matches(in: lower, range: range) {
            guard let numRange = Range(match.range(at: 1), in: lower),
                  let unitRange = Range(match.range(at: 2), in: lower),
                  let number = Int(lower[numRange]) else { continue }
            let unit = String(lower[unitRange])
            if unit.hasPrefix("h") {
                total += number * 3600
                found = true
            } else if unit.hasPrefix("m") {
                total += number * 60
                found = true
            } else if unit.hasPrefix("s") {
                total += number
                found = true
            }
        }
        return found ? total : nil
    }

    public static func shortDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }

    /// Duration seconds from any known renderer shape. Checks fixed columns,
    /// `lengthSeconds`, `lengthText`, thumbnail badges, subtitle runs and
    /// flex-column subtitles, in that order; 0 when unparseable.
    public static func parseRendererDuration(_ renderer: [String: Any]) -> Int {
        // 1. fixedColumns[0] — primary source for MusicResponsiveListItemRenderer
        if let fixedColumns = renderer["fixedColumns"] as? [[String: Any]] {
            for col in fixedColumns {
                if let fixed = col["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
                   let textDict = fixed["text"] as? [String: Any],
                   let runs = textDict["runs"] as? [[String: Any]],
                   let first = runs.first,
                   let text = first["text"] as? String,
                   let parsed = parseClock(text) {
                    return parsed
                }
            }
        }

        // 2. lengthSeconds — raw seconds string from player response
        if let lengthSeconds = renderer["lengthSeconds"] as? String, let seconds = Int(lengthSeconds) {
            return seconds
        }
        if let lengthSeconds = renderer["lengthSeconds"] as? Int {
            return lengthSeconds
        }

        // 3. lengthText — used by PlaylistPanelVideoRenderer (up next / queue)
        if let lengthText = renderer["lengthText"] as? [String: Any],
           let runs = lengthText["runs"] as? [[String: Any]],
           let first = runs.first,
           let text = first["text"] as? String,
           let parsed = parseClock(text) {
            return parsed
        }

        // 4. Badges — thumbnail badges with duration
        if let badges = renderer["badges"] as? [[String: Any]] {
            for badgeDict in badges {
                if let badge = badgeDict["musicInlineBadgeRenderer"] as? [String: Any],
                   let text = badge["text"] as? [String: Any],
                   let runs = text["runs"] as? [[String: Any]],
                   let first = runs.first,
                   let textStr = first["text"] as? String,
                   let parsed = parseClock(textStr) {
                    return parsed
                }
            }
        }

        // 5. Subtitle runs — last segment after "•" separator may be duration
        if let subtitle = renderer["subtitle"] as? [String: Any],
           let runs = subtitle["runs"] as? [[String: Any]] {
            let allText = runs.compactMap { $0["text"] as? String }
            let segments = allText.split { $0 == " • " || $0.trimmingCharacters(in: .whitespaces) == "•" }
            if let lastSegment = segments.last,
               let lastText = lastSegment.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
               let parsed = parseClock(lastText.trimmingCharacters(in: .whitespaces)) {
                return parsed
            }
        }

        // 6. flexColumns[1] subtitle text (for MusicResponsiveListItemRenderer)
        if let flexColumns = renderer["flexColumns"] as? [[String: Any]], flexColumns.count > 1 {
            let col = flexColumns[1]
            let flexRenderer = (col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])
                ?? (col["musicResponsiveListItemColumnRenderer"] as? [String: Any])
            if let textDict = flexRenderer?["text"] as? [String: Any],
               let runs = textDict["runs"] as? [[String: Any]] {
                let allText = runs.compactMap { $0["text"] as? String }
                let segments = allText.split { $0 == " • " || $0.trimmingCharacters(in: .whitespaces) == "•" }
                if let lastSegment = segments.last,
                   let lastText = lastSegment.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
                   let parsed = parseClock(lastText.trimmingCharacters(in: .whitespaces)) {
                    return parsed
                }
            }
        }

        return 0
    }
}

extension Int {
    /// "m:ss" / "h:mm:ss"; empty string when not positive.
    public var formattedDuration: String {
        guard self > 0 else { return "" }
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let secs = self % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", secs))"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    public var wordsDuration: String {
        guard self > 0 else { return "" }
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        switch (hours, minutes) {
        case (0, 0):
            return "\(self % 60) sec"
        case (0, _):
            return "\(minutes) min"
        case (_, 0):
            return "\(hours) h"
        default:
            return "\(hours) h \(minutes) min"
        }
    }
}
