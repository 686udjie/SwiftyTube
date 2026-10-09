//
//  RegionalCharts.swift
//  SwiftyTube
//
//  Created by 686udjie on 09/10/2026.
//

import Foundation

/// Country-scoped charts lookups (`FEmusic_charts`).
public enum RegionalCharts: Sendable {
    /// Playlist id behind the region's Trending shelf: prefers a "Trending N
    /// <Country>" playlist, then the daily chart, then the first playlist
    /// entry found.
    public static func trendingPlaylistId(
        country: String,
        using client: InnerTubeClient
    ) async throws -> String {
        let json = try await client.browse(
            browseId: "FEmusic_charts",
            formData: ["selectedValues": [country]]
        )
        guard let id = selectTrending(from: playlistEntries(in: json)) else {
            throw InnerTubeError.invalidResponse
        }
        return id
    }

    /// Pure selection step, factored out for tests.
    static func selectTrending(from entries: [(id: String, title: String)]) -> String? {
        if let trending = entries.first(where: { $0.title.localizedCaseInsensitiveContains("Trending") }) {
            return trending.id
        }
        if let daily = entries.first(where: { $0.title.localizedCaseInsensitiveContains("Daily Top") }) {
            return daily.id
        }
        return entries.first?.id
    }

    /// `(browseId, title)` of every playlist entry across charts carousels.
    static func playlistEntries(in json: [String: Any]) -> [(id: String, title: String)] {
        guard let contents = json["contents"] as? [String: Any],
              let single = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = single["tabs"] as? [[String: Any]],
              let content = (tabs.first?["tabRenderer"] as? [String: Any])?["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]] else { return [] }
        var out: [(id: String, title: String)] = []
        for section in sections {
            let unwrapped = (section["itemSectionRenderer"] as? [String: Any])
                .flatMap { ($0["contents"] as? [[String: Any]])?.first }
                ?? section
            guard let shelf = unwrapped["musicCarouselShelfRenderer"] as? [String: Any],
                  let items = shelf["contents"] as? [[String: Any]] else { continue }
            for item in items {
                if let renderer = item["musicTwoRowItemRenderer"] as? [String: Any],
                   let id = playlistId(in: renderer),
                   let title = InnerTubeJSON.runsText(renderer["title"] as? [String: Any]) {
                    out.append((id, title))
                } else if let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
                          let id = playlistId(in: renderer),
                          let title = firstFlexText(in: renderer) {
                    out.append((id, title))
                }
            }
        }
        return out
    }

    private static func playlistId(in renderer: [String: Any]) -> String? {
        guard let nav = renderer["navigationEndpoint"] as? [String: Any] else { return nil }
        if let browse = nav["browseEndpoint"] as? [String: Any],
           let bid = browse["browseId"] as? String, bid.hasPrefix("VL") {
            return bid
        }
        if let watch = nav["watchEndpoint"] as? [String: Any],
           let pid = watch["playlistId"] as? String, pid.hasPrefix("VL") || pid.hasPrefix("PL") {
            return pid
        }
        return nil
    }

    private static func firstFlexText(in renderer: [String: Any]) -> String? {
        guard let flex = renderer["flexColumns"] as? [[String: Any]],
              let first = flex.first,
              let col = first["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] else { return nil }
        return InnerTubeJSON.runsText(col["text"] as? [String: Any])
    }
}
