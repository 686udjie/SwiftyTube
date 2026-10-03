//
//  PlayerConfigStore.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Known player hashes → cipher info. Bundled JSON by default, overlaid by
/// zemer-cipher's remote copy so rotations self-heal. Entries are regex-locked
/// (sig = name(i,i,INPUT), nClass = identifier) since they run as JS.
public actor PlayerConfigStore {
    public static let shared = PlayerConfigStore()

    private static let remoteURL = URL(string:
        "https://raw.githubusercontent.com/ZemerTeam/zemer-cipher/master/library/src/main/assets/player_configs.json"
    )!

    private let refreshTTL: TimeInterval = 6 * 60 * 60
    private let forcedRefreshCooldown: TimeInterval = 5 * 60

    private struct ValidationRegexes: Sendable {
        let sig: NSRegularExpression
        let nClass: NSRegularExpression
        let hash: NSRegularExpression
    }

    /// The patterns are compile-time constants - a throw here can only be a typo.
    private static func lockedRegex(_ pattern: String) -> NSRegularExpression {
        if let regex = try? NSRegularExpression(pattern: pattern) { return regex }
        SwiftyTubeLog.error("Invalid regex pattern: \(pattern) – using never-match fallback")
        if let fallback = try? NSRegularExpression(pattern: "(?!.*)") { return fallback }
        return (try? NSRegularExpression(pattern: ""))!
    }

    /// Bumps on table change; the WebView rebuilds when it advances.
    private(set) var configEpoch = 0

    private var bundledConfigs: [String: PlayerConfig] = [:]
    private var aliasToHash: [String: String] = [:]
    private var mergedConfigs: [String: PlayerConfig] = [:]

    private var loaded = false
    private var lastFetchTime: TimeInterval = 0
    private var etag: String?

    private var lastForcedAttempt: TimeInterval = 0
    private var lastRejectionAttempt: TimeInterval = 0
    private var refreshInFlight = false
    /// Cooldowns arm only when the server was actually reached.
    private var lastAttemptReachedServer = false

    private let bundle: Bundle
    private let session: URLSession

    public init(bundle: Bundle = .main, session: URLSession = .shared) {
        self.bundle = bundle
        self.session = session
    }

    // MARK: - Lookup

    public func config(for hash: String) async -> PlayerConfig? {
        if !loaded { await loadConfigs() }
        if let direct = mergedConfigs[hash] { return direct }
        if let hash = aliasToHash[hash] { return mergedConfigs[hash] }
        return nil
    }

    public func epoch() async -> Int {
        if !loaded { await loadConfigs() }
        return configEpoch
    }

    /// Refresh on hash miss. True if the hash is now known.
    @discardableResult
    public func forceRefresh(missingHash: String) async -> Bool {
        if !loaded { await loadConfigs() }
        if mergedConfigs[missingHash] != nil || aliasToHash[missingHash] != nil { return true }

        let now = Date().timeIntervalSince1970
        guard !withinWindow(now: now, stamp: lastForcedAttempt, window: forcedRefreshCooldown) else {
            SwiftyTubeLog.debug("forceRefresh skipped (cooldown)")
            return false
        }
        lastForcedAttempt = now
        await fetchAndApply()
        if !lastAttemptReachedServer { lastForcedAttempt = 0 }
        return mergedConfigs[missingHash] != nil || aliasToHash[missingHash] != nil
    }

    /// Refresh after a 403 (stale config may sign wrong).
    public func notifyStreamRejection() async {
        if !loaded { await loadConfigs() }
        let now = Date().timeIntervalSince1970
        guard !withinWindow(now: now, stamp: lastRejectionAttempt, window: forcedRefreshCooldown) else { return }
        lastRejectionAttempt = now
        await fetchAndApply()
        if !lastAttemptReachedServer { lastRejectionAttempt = 0 }
    }

    /// In-range check (immune to backward clock jumps).
    private func withinWindow(now: TimeInterval, stamp: TimeInterval, window: TimeInterval) -> Bool {
        let delta = now - stamp
        return delta >= 0 && delta < window
    }

    // MARK: - Loading

    private func loadConfigs() async {
        loaded = true
        bundledConfigs = loadBundled() ?? [:]
        rebuildAliasMap(bundledConfigs)
        SwiftyTubeLog.debug("Loaded \(bundledConfigs.count) bundled configs")

        if let cachedText = readFile(configsCacheURL),
           let cached = Self.parse(text: cachedText) {
            applyRemote(cached, persistBody: false)
            if let meta = readMeta() {
                etag = meta.etag
                lastFetchTime = meta.timestamp
            }
        } else if FileManager.default.fileExists(atPath: configsCacheURL?.path ?? "-") {
            removeFile(configsCacheURL)
            removeFile(metaCacheURL)
        }

        if !withinWindow(now: Date().timeIntervalSince1970, stamp: lastFetchTime, window: refreshTTL) {
            await fetchAndApply()
        }
    }

    // MARK: - Fetch & Apply

    private func fetchAndApply() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }

        var request = URLRequest(url: Self.remoteURL)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            lastAttemptReachedServer = false
            SwiftyTubeLog.notice("Remote config fetch failed (network) - keeping previous configs")
            return
        }
        lastAttemptReachedServer = true

        if http.statusCode == 304 {
            etag = http.value(forHTTPHeaderField: "ETag") ?? etag
            lastFetchTime = Date().timeIntervalSince1970
            writeMeta()
            return
        }
        guard http.statusCode == 200,
              let body = String(data: data, encoding: .utf8), !body.isEmpty else {
            SwiftyTubeLog.notice("Remote config fetch HTTP \(http.statusCode) - keeping previous configs")
            return
        }

        guard let remote = Self.parse(text: body) else {
            SwiftyTubeLog.notice("Remote configs rejected (validation) - keeping previous configs")
            return
        }

        etag = http.value(forHTTPHeaderField: "ETag") ?? ""
        lastFetchTime = Date().timeIntervalSince1970
        applyRemote(remote, persistBody: true, rawBody: body)
        writeMeta()
    }

    /// Merge remote over bundled, persist, bump epoch on change.
    private func applyRemote(_ remote: [String: PlayerConfig], persistBody: Bool, rawBody: String? = nil) {
        var merged = bundledConfigs
        merged.merge(remote) { _, remoteEntry in remoteEntry }
        rebuildAliasMap(merged)

        let changed = merged != mergedConfigs
        mergedConfigs = merged
        if changed { configEpoch += 1 }
        SwiftyTubeLog.debug(
            "Remote configs applied (\(remote.count) hashes, merged=\(merged.count), changed=\(changed))"
        )

        if persistBody, let rawBody {
            writeFile(configsCacheURL, rawBody)
        }
    }

    private func rebuildAliasMap(_ configs: [String: PlayerConfig]) {
        var map: [String: String] = [:]
        for (hash, entry) in configs {
            for alias in entry.aliases ?? [] where alias != hash {
                map[alias] = hash
            }
        }
        aliasToHash = map
    }

    // MARK: - Parsing / validation

    /// Validated table or nil. Bad entries skipped, dup keys reject all.
    static func parse(text: String) -> [String: PlayerConfig]? {
        let regexes = ValidationRegexes(
            sig: Self.lockedRegex(#"^[A-Za-z0-9$_]{1,8}\(\d+,\d+,INPUT\)$"#),
            nClass: Self.lockedRegex("^[A-Za-z0-9$_]{1,8}$"),
            hash: Self.lockedRegex("^[a-f0-9]{8}$")
        )
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let schemaVersion = intPrimitive(root["schemaVersion"]), schemaVersion > 0, schemaVersion <= 1 else {
            return nil
        }
        guard let players = root["players"] as? [String: Any] else { return nil }

        var configs: [String: PlayerConfig] = [:]
        for (hash, entryAny) in players {
            guard let entry = entryAny as? [String: Any],
                  matches(regexes.hash, hash),
                  let sig = stringPrimitive(entry["sig"]), matches(regexes.sig, sig),
                  let nClass = stringPrimitive(entry["nClass"]), matches(regexes.nClass, nClass),
                  let sts = intPrimitive(entry["sts"]), sts > 0 else {
                continue
            }
            var aliases: [String] = []
            if let aliasArray = entry["aliases"] as? [Any] {
                var valid = true
                for aliasAny in aliasArray {
                    guard let alias = stringPrimitive(aliasAny), matches(regexes.hash, alias) else {
                        valid = false
                        break
                    }
                    aliases.append(alias)
                }
                guard valid else { continue }
            }

            let keys = [hash] + aliases
            if Set(keys).count != keys.count || keys.contains(where: { configs[$0] != nil }) {
                return nil
            }
            configs[hash] = PlayerConfig(sig: sig, nClass: nClass, sts: sts, aliases: aliases)
        }
        return configs
    }

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range)?.range.length == range.length
    }

    private static func stringPrimitive(_ any: Any?) -> String? {
        any as? String
    }

    /// Non-string primitives only: a string-typed "1" must fail like upstream.
    private static func intPrimitive(_ any: Any?) -> Int? {
        guard !(any is String), let number = any as? NSNumber else { return nil }
        return number.intValue
    }

    // MARK: - Disk helpers

    private var storeDir: URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let dir = documents?.appendingPathComponent("Player", isDirectory: true)
        // Deliberately not prefixed "player_" - PlayerJsFetcher purges player_* files here.
        return dir
    }

    private var configsCacheURL: URL? { storeDir?.appendingPathComponent("configs_remote.json") }
    private var metaCacheURL: URL? { storeDir?.appendingPathComponent("configs_remote.meta") }

    private func loadBundled() -> [String: PlayerConfig]? {
        // Static libraries cannot own resources: the app embeds
        // player_configs.json (e.g. via a synchronized folder).
        for candidate in [bundle, Bundle(for: PlayerConfigStore.self)] {
            if let url = candidate.url(forResource: "player_configs", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                return Self.parse(text: text)
            }
        }
        return nil
    }

    private struct Meta {
        let etag: String
        let timestamp: TimeInterval
    }

    private func readMeta() -> Meta? {
        guard let text = readFile(metaCacheURL) else { return nil }
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count == 2, let timestamp = TimeInterval(lines[1]) else { return nil }
        return Meta(etag: String(lines[0]), timestamp: timestamp)
    }

    private func writeMeta() {
        guard let url = metaCacheURL else { return }
        writeFile(url, "\(etag ?? "")\n\(lastFetchTime)")
    }

    private func readFile(_ url: URL?) -> String? {
        guard let url, let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeFile(_ url: URL?, _ content: String) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func removeFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
