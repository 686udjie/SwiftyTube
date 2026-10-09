//
//  BrowseLens.swift
//  SwiftyTube
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation

/// Shared descents into InnerTube browse JSON.
public enum BrowseLens: Sendable {
    /// The `sectionListRenderer` dict of a browse response. Tolerates both
    /// single- and two-column layouts plus tabbed/sectionList nesting drift;
    /// returns nil (with a diagnostic) instead of crashing call sites
    public static func sectionList(_ json: [String: Any]) -> [String: Any]? {
        if let sl = InnerTubeDecode.dict(at: ["contents", "singleColumnBrowseResultsRenderer"], in: json)
            .flatMap({ $0["tabs"] as? [[String: Any]] })?.first
            .flatMap({ $0["tabRenderer"] as? [String: Any] })
            .flatMap({ $0["content"] as? [String: Any] })
            .flatMap({ $0["sectionListRenderer"] as? [String: Any] }) {
            return sl
        }
        if let twoCol = InnerTubeDecode.dict(at: ["contents", "twoColumnBrowseResultsRenderer"], in: json),
           let tabs = twoCol["tabs"] as? [[String: Any]],
           let first = tabs.first,
           let tabRenderer = first["tabRenderer"] as? [String: Any],
           let content = tabRenderer["content"] as? [String: Any],
           let sl = content["sectionListRenderer"] as? [String: Any] {
            return sl
        }
        return nil
    }

    /// The section array of a browse response.
    public static func browseSections(_ json: [String: Any]) -> [[String: Any]]? {
        guard let sectionList = sectionList(json),
              let sections = sectionList["contents"] as? [[String: Any]] else { return nil }
        return sections
    }

    /// The first section of a browse response.
    public static func firstBrowseSection(_ json: [String: Any]) -> [String: Any]? {
        browseSections(json)?.first
    }

    /// First section's first item, tolerating single- and two-column
    /// layouts. Used by the album/podcast/playlist detail header parsers.
    public static func firstSectionItem(_ json: [String: Any]) -> [String: Any]? {
        guard let contents = json["contents"] as? [String: Any] else { return nil }
        let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any]
        let twoColumn = contents["twoColumnBrowseResultsRenderer"] as? [String: Any]
        let tabsArray: [[String: Any]]? = {
            if let tabs = twoColumn?["tabs"] as? [[String: Any]] { return tabs }
            if let tabs = singleColumn?["tabs"] as? [[String: Any]] { return tabs }
            return nil
        }()
        return tabsArray?.first
            .flatMap { $0["tabRenderer"] as? [String: Any] }
            .flatMap { $0["content"] as? [String: Any] }
            .flatMap { $0["sectionListRenderer"] as? [String: Any] }
            .flatMap { ($0["contents"] as? [[String: Any]])?.first }
    }

    /// Account-name runs from an `account/account_menu` response, used to
    /// probe session validity.
    public static func accountNameRuns(_ json: [String: Any]) -> [[String: Any]]? {
        guard let header = json["header"] as? [String: Any],
              let renderer = header["musicAccountHeaderRenderer"] as? [String: Any],
              let accountName = renderer["accountName"] as? [String: Any],
              let runs = accountName["runs"] as? [[String: Any]] else { return nil }
        return runs
    }
}
