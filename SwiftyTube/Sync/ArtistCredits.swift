//
//  ArtistCredits.swift
//  SwiftyTube
//
//  Created by 686udjie on 15/10/2026.
//

import Foundation

/// One credited artist: display name plus the artist page id when the run
/// actually links one (nil for plain-text credits and topic channels).
public struct ArtistCredit: Sendable, Hashable {
    public let name: String
    public let browseId: String?

    public init(name: String, browseId: String?) {
        self.name = name
        self.browseId = browseId
    }
}

public enum ArtistCredits {
    /// Runs that separate credits rather than naming anyone.
    private static let separators: Set<String> = ["•", "·", ",", "&", "and", "feat.", "ft.", "featuring"]

    /// Runs that label the row instead of crediting anyone.
    private static let junkLabels: Set<String> = [
        "song", "video", "track", "music", "podcast", "episode",
        "album", "playlist", "released", "year", "plays", "views",
        "downloads", "listeners", "subscribers", "watchers", "likes"
    ]

    private static let junkPatterns: [String] = [
        "^[\\d,\\.]+[KMBT]?\\s*(views|downloads|listeners|subscribers|plays|watchers|likes?)?$",
        "^\\d{4}$",
        "^[\\d,\\.]+[KMBT]?$",
        "^[\\d,\\.]+[KMBT]?\\s+likes?$",
        // Clock durations ("1:33:21", "3:21"): some rows carry the length in
        // the byline, and without this they parse as an artist credit.
        "^\\d{1,3}[:.,]\\d{2}(?:[:.,]\\d{2})?$"
    ]

    /// True when raw run text can name an artist (not a separator, label or
    /// count). Structural callers (shelf segment splitting) use this.
    public static func isArtistName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.isEmpty || separators.contains(lower) || junkLabels.contains(lower) { return false }
        for pattern in junkPatterns where lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        return true
    }

    /// Display form of a raw credit name: topic suffix and bare years off.
    public static func cleanedName(_ name: String) -> String {
        var s = name
        let lower = s.lowercased()
        for suffix in [" - topic", " – topic", " — topic"] where lower.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
        }
        if let r = try? NSRegularExpression(pattern: "\\s*[\\(\\[]\\d{4}[\\)\\]]\\s*$") {
            s = r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Credits from raw byline/subtitle/strapline runs. Separators split,
    /// junk is dropped, album/playlist-linked runs are skipped (they name a
    /// release, not a performer), names are cleaned, empties dropped and
    /// repeats merged (keeping the copy that carries a page id).
    public static func parse(runs: [[String: Any]]) -> [ArtistCredit] {
        var credits: [ArtistCredit] = []
        for run in runs {
            guard let text = run["text"] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isArtistName(trimmed) else { continue }
            if let browseId = browseId(in: run), isAlbumOrPlaylistLink(browseId: browseId, run: run) {
                continue
            }
            // Channel ids stay attached (topic channels included): a channel
            // page for the right person beats a name-search lottery that can
            // land on a different person with a similar name.
            let browseId = browseId(in: run)
            let name = cleanedName(trimmed)
            guard !name.isEmpty else { continue }
            if let index = credits.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
                if credits[index].browseId == nil, browseId != nil {
                    credits[index] = ArtistCredit(name: credits[index].name, browseId: browseId)
                }
                continue
            }
            credits.append(ArtistCredit(name: name, browseId: browseId))
        }
        return credits
    }

    // MARK: - Link policy

    private static func browseId(in run: [String: Any]) -> String? {
        ((run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
    }

    private static func musicPageType(in run: [String: Any]) -> String? {
        // Shelf rows nest the config inside browseEndpoint; watch panels
        // hoist it to navigationEndpoint level. Check both.
        let nav = run["navigationEndpoint"] as? [String: Any]
        let browse = nav?["browseEndpoint"] as? [String: Any]
        let supported = browse?["browseEndpointContextSupportedConfigs"] as? [String: Any]
            ?? nav?["browseEndpointContextSupportedConfigs"] as? [String: Any]
        return (supported?["browseEndpointContextMusicConfig"] as? [String: Any])?["pageType"] as? String
    }

    /// Album/playlist links name a release, never a performer.
    private static func isAlbumOrPlaylistLink(browseId: String, run: [String: Any]) -> Bool {
        if browseId.hasPrefix("MPREb_") || browseId.hasPrefix("VL") || browseId.hasPrefix("PL") {
            return true
        }
        if let pageType = musicPageType(in: run),
           pageType != "MUSIC_PAGE_TYPE_ARTIST",
           pageType != "MUSIC_PAGE_TYPE_USER_CHANNEL" {
            return true
        }
        return false
    }
}
