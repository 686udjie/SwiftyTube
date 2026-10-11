//
//  ArtworkURLs.swift
//  SwiftyTube
//
//  Created by 686udjie on 10/10/2026.
//

import Foundation

/// Artwork URL builders shared by apps.
public enum ArtworkURLs: Sendable {
    /// i.ytimg fallback artwork for a video id.
    public static func fallback(for videoId: String) -> String {
        "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    /// Rewrites a `w<N>-h<N>` thumbnail URL to the requested square size.
    public static func sized(_ url: String?, width: Int, height: Int) -> String? {
        url?.replacingOccurrences(
            of: #"w\d+-h\d+"#,
            with: "w\(width)-h\(height)",
            options: .regularExpression
        )
    }

    // MARK: - Size ladder

    /// One rung per surface so each shares a single cache entry instead of
    /// every view fetching its own size
    public static let rowPx = 160
    public static let cardPx = 480
    public static let headerPx = 720
    public static let playerPx = 1200

    private static let rungs = [rowPx, cardPx, headerPx, playerPx]

    /// Smallest ladder rung covering `pixels` (never below the row rung).
    public static func rung(for pixels: CGFloat) -> Int {
        let need = max(Int(pixels.rounded(.up)), 1)
        for rung in rungs where rung >= need { return rung }
        return playerPx
    }

    // MARK: - CDN upgrade

    public static func artwork(_ url: String?, at px: Int) -> String? {
        guard var url = url, !url.isEmpty else { return nil }
        url = url.replacingOccurrences(of: "(?<=[sh]\\d+)-c", with: "", options: .regularExpression)
        guard url.contains("googleusercontent.com") || url.contains("ggpht.com") else { return url }
        if url.range(of: #"w\d+-h\d+"#, options: .regularExpression) != nil {
            url = url.replacingOccurrences(
                of: #"w\d+-h\d+"#,
                with: "w\(px)-h\(px)",
                options: .regularExpression
            )
        } else if let base = url.split(separator: "=").first {
            url = String(base) + "=w\(px)-h\(px)"
        }
        return url
    }

    /// Convenience: artwork at the player rung
    public static func highRes(_ url: String?) -> String? {
        artwork(url, at: playerPx)
    }

    public static func maxResVariant(_ url: String?) -> String? {
        ytimgVariant(url, file: "maxresdefault.jpg")
    }

    /// 640px variant. Exists far more often than maxres, >hqdefault
    public static func sdVariant(_ url: String?) -> String? {
        ytimgVariant(url, file: "sddefault.jpg")
    }

    private static func ytimgVariant(_ url: String?, file: String) -> String? {
        guard let url, url.contains("i.ytimg.com/vi/") else { return nil }
        let base = url.split(separator: "?").first.map(String.init) ?? url
        guard let lastSlash = base.lastIndex(of: "/") else { return nil }
        return String(base[..<lastSlash]) + "/\(file)"
    }
}
