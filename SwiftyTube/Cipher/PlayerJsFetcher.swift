//
//  PlayerJsFetcher.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

// player.js download + 6h disk cache.
public actor PlayerJsFetcher {
    public static let shared = PlayerJsFetcher()

    private let cacheLifetime: TimeInterval = 6 * 60 * 60
    private let cacheDirectory: URL?
    private let session: URLSession
    private let configStore: PlayerConfigStore

    public init(
        cacheDirectory: URL? = nil,
        session: URLSession = .shared,
        configStore: PlayerConfigStore = .shared
    ) {
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory()
        self.session = session
        self.configStore = configStore
    }

    public static func defaultCacheDirectory() -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documents?.appendingPathComponent("Player", isDirectory: true)
    }

    // Returns the current player hash.
    public func getPlayerHash() async throws -> String {
        try ensureCacheDir()
        if let cached = try? loadCachedHash() {
            return cached
        }
        let (hash, _) = try await fetchPlayerJs()
        return hash
    }

    // Returns the current player.js content, fetching if needed.
    public func getPlayerJs() async throws -> String {
        try ensureCacheDir()
        if let cached = try loadCachedPlayerJs() {
            return cached
        }
        let (hash, js) = try await fetchPlayerJs()
        try saveCache(hash: hash, js: js)
        return js
    }

    // Returns the signature timestamp from the current player.js,
    // falling back to the player config's sts when extraction fails.
    public func getSignatureTimestamp() async throws -> Int {
        let js = try await getPlayerJs()
        if let timestamp = try? Self.extractSignatureTimestamp(from: js) {
            return timestamp
        }
        let hash = try await getPlayerHash()
        if let config = await configStore.config(for: hash), let sts = config.sts {
            SwiftyTubeLog.debug("signatureTimestamp from config: \(sts)")
            return sts
        }
        throw CipherError.signatureTimestampNotFound
    }

    // MARK: - Fetch Pipeline

    private func fetchPlayerJs() async throws -> (hash: String, js: String) {
        let hash = try await fetchPlayerHash()
        let js = try await downloadPlayerJs(hash: hash)
        return (hash, js)
    }

    private func fetchPlayerHash() async throws -> String {
        let url = URL(string: "https://www.youtube.com/iframe_api")!
        let (data, _) = try await HttpClient.data(from: url, session: session)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CipherError.invalidResponse("iframe_api not UTF-8")
        }
        let nsText = text as NSString
        guard let pattern = try? NSRegularExpression(pattern: #"\\?/s\\?/player\\?/([\w-]+)\\?/"#, options: []) else {
            throw CipherError.hashNotFound
        }
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            throw CipherError.hashNotFound
        }
        return nsText.substring(with: match.range(at: 1))
    }

    // Downloads player.js for a given hash.
    private func downloadPlayerJs(hash: String) async throws -> String {
        let url = URL(string: "https://www.youtube.com/s/player/\(hash)/player_ias.vflset/en_GB/base.js")!
        let (data, _) = try await HttpClient.data(from: url, session: session)
        guard let js = String(data: data, encoding: .utf8) else {
            throw CipherError.invalidResponse("player.js not UTF-8")
        }
        return js
    }

    // MARK: - Cache

    private func ensureCacheDir() throws {
        guard let dir = cacheDirectory else { throw CipherError.cacheUnavailable }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func cachePath(hash: String) -> URL? {
        cacheDirectory?.appendingPathComponent("player_\(hash).js")
    }

    private var hashInfoPath: URL? {
        cacheDirectory?.appendingPathComponent("current_hash.txt")
    }

    private func loadCachedHash() throws -> String? {
        guard let info = try? loadHashInfo() else { return nil }
        return info.hash
    }

    private func loadHashInfo() throws -> (hash: String, timestamp: TimeInterval)? {
        guard let infoPath = hashInfoPath,
              let infoData = try? Data(contentsOf: infoPath),
              let info = String(data: infoData, encoding: .utf8) else {
            return nil
        }
        let lines = info.split(separator: "\n", maxSplits: 1)
        guard lines.count == 2,
              let timestamp = TimeInterval(lines[1]) else {
            return nil
        }
        return (String(lines[0]), timestamp)
    }

    private func loadCachedPlayerJs() throws -> String? {
        guard let info = try? loadHashInfo() else { return nil }
        // Check TTL.
        guard Date().timeIntervalSince1970 - info.timestamp < cacheLifetime else {
            return nil
        }
        guard let jsPath = cachePath(hash: info.hash),
              let js = try? String(contentsOf: jsPath, encoding: .utf8) else {
            return nil
        }
        SwiftyTubeLog.debug("Using cached player.js (hash=\(info.hash))")
        return js
    }

    private func saveCache(hash: String, js: String) throws {
        // Save JS file.
        if let jsPath = cachePath(hash: hash) {
            try js.write(to: jsPath, atomically: true, encoding: .utf8)
        }
        // Remove stale player JS files so the cache dir only holds the current player.
        if let dir = cacheDirectory {
            let currentName = "player_\(hash).js"
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.lastPathComponent.hasPrefix("player_") && url.lastPathComponent != currentName {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // Save hash info.
        let info = "\(hash)\n\(Date().timeIntervalSince1970)"
        if let infoPath = hashInfoPath {
            try info.write(to: infoPath, atomically: true, encoding: .utf8)
        }
        SwiftyTubeLog.debug("Cached player.js (hash=\(hash))")
    }

    // MARK: - Signature Timestamp Extraction

    static func extractSignatureTimestamp(from js: String) throws -> Int {
        let nsJs = js as NSString
        guard let pattern = try? NSRegularExpression(pattern: #"signatureTimestamp["':\s]+(\d+)"#, options: []) else {
            throw CipherError.signatureTimestampNotFound
        }
        guard let match = pattern.firstMatch(in: js, range: NSRange(location: 0, length: nsJs.length)) else {
            throw CipherError.signatureTimestampNotFound
        }
        let value = nsJs.substring(with: match.range(at: 1))
        return Int(value) ?? 0
    }
}
