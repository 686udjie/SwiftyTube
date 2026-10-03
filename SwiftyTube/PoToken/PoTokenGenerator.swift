//
//  PoTokenGenerator.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import WebKit

public actor PoTokenGenerator: NSObject {
    public static let shared = PoTokenGenerator()

    private var webView: WKWebView?
    private var webViewReady = false
    private var loadingWebView = false
    private var minterReady = false

    private let bundle: Bundle
    private let botGuard: BotGuardService

    public init(bundle: Bundle = .main, botGuard: BotGuardService = .shared) {
        self.bundle = bundle
        self.botGuard = botGuard
    }

    /// `po_token.html` from the embedding bundle (`Bundle.main` finds app files).
    public static func html(bundle: Bundle = .main) -> String? {
        let candidates = [bundle, Bundle(for: PoTokenGenerator.self)]
        for candidate in candidates {
            if let path = candidate.path(forResource: "po_token", ofType: "html"),
               let html = try? String(contentsOfFile: path, encoding: .utf8) {
                return html
            }
        }
        return nil
    }

    private func ensureWebView() async throws {
        if webViewReady { return }
        if loadingWebView {
            while loadingWebView { try await Task.sleep(nanoseconds: 100_000_000) }
            return
        }

        loadingWebView = true
        defer { loadingWebView = false }

        guard let html = Self.html(bundle: bundle) else {
            throw BotGuardError.invalidResponse
        }

        let wv = await MainActor.run {
            let handler = PoTokenMessageHandler(generator: self)
            let config = WKWebViewConfiguration()
            let userContent = WKUserContentController()
            userContent.add(handler, name: "botguard")
            config.userContentController = userContent
            config.suppressesIncrementalRendering = true

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.isHidden = true
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
            return webView
        }
        self.webView = wv

        try await waitForPageLoad(wv, timeout: 10)
        self.webViewReady = true
    }

    @MainActor
    private func waitForPageLoad(_ webView: WKWebView, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = (try? await webView.evaluateJavaScript("document.readyState")) as? String
            if state == "complete" { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        SwiftyTubeLog.notice("PoToken WebView load wait timed out - continuing")
    }

    public func generate(videoId: String, sessionId: String?) async throws -> PoTokenResult {
        try await ensureWebView()
        try await ensureMinter()

        let sessionIdStr = sessionId ?? "SESSION"
        do {
            let playerToken = try await generatePoToken(sessionIdStr)
            let streamingToken = try await generatePoToken(videoId)
            return PoTokenResult(
                playerRequestPoToken: playerToken,
                streamingDataPoToken: streamingToken
            )
        } catch {
            SwiftyTubeLog.error("Token generation failed, re-creating minter...")
            minterReady = false
            try await ensureMinter()
            let playerToken = try await generatePoToken(sessionIdStr)
            let streamingToken = try await generatePoToken(videoId)
            return PoTokenResult(
                playerRequestPoToken: playerToken,
                streamingDataPoToken: streamingToken
            )
        }
    }

    private func ensureMinter() async throws {
        if minterReady { return }

        // 1. Create BotGuard challenge.
        SwiftyTubeLog.debug("Creating BotGuard challenge...")
        let challenge = try await botGuard.createChallenge()
        SwiftyTubeLog.debug(
            "Challenge: program=\(challenge.program.prefix(50))..." +
                " globalName=\(challenge.globalName ?? "?")"
        )

        // 2. Build challenge JSON and call runBotGuard in WebView.
        let challengeJSON = buildChallengeJSON(challenge)
        SwiftyTubeLog.debug("Running BotGuard in WebView...")

        let bgResult = try await evalJS("""
            runBotGuard(\(challengeJSON)).then(function(result) {
                window.__webPoSignalOutput = result.webPoSignalOutput;
                return JSON.stringify({ response: result.botguardResponse });
            })
        """)
        SwiftyTubeLog.debug("BotGuard response received")

        guard let bgData = bgResult.data(using: .utf8),
              let bgObj = try JSONSerialization.jsonObject(with: bgData) as? [String: Any],
              let botguardResponse = bgObj["response"] as? String else {
            throw BotGuardError.descrambleFailed
        }

        // 3. GenerateIT API.
        let (integrityTokenU8, _) = try await botGuard.generateIT(
            botguardResponse: botguardResponse
        )
        SwiftyTubeLog.debug("Got integrity token")

        // 4. Create poToken minter.
        _ = try await evalJS("""
            createPoTokenMinter(window.__webPoSignalOutput, \(integrityTokenU8))
        """)
        SwiftyTubeLog.debug("Minter created")

        minterReady = true
    }

    private func generatePoToken(_ identifier: String) async throws -> String {
        guard let data = identifier.data(using: .utf8) else {
            throw BotGuardError.descrambleFailed
        }
        let idBytes = data.map { String($0) }.joined(separator: ",")
        let u8id = "new Uint8Array([\(idBytes)])"

        let result = try await evalJS("""
            obtainPoToken(\(u8id))
        """)

        return u8ToBase64(result)
    }

    // MARK: - JS Bridge

    /// Runs JS that posts back {id, type, value/error}. Fails instead of hanging.
    private func evalJS(_ script: String) async throws -> String {
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            Task { [weak self] in
                guard let self = self else {
                    cont.resume(throwing: BotGuardError.descrambleFailed)
                    return
                }
                await self.setContinuation(id, cont)

                let wv = await self.webView
                guard wv != nil else {
                    await self.resolveContinuation(id, result: .failure(BotGuardError.descrambleFailed))
                    return
                }

                // If the script never posts a message, fail rather than hang.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard let self else { return }
                    let didResolve = await self.resolveContinuation(
                        id,
                        result: .failure(BotGuardError.descrambleFailed)
                    )
                    if didResolve {
                        SwiftyTubeLog.error("PoToken JS evaluation timed out")
                    }
                }

                let fullJS = """
                (function() {
                  var __id = "\(id)";
                  try {
                    var __result = \(script);
                    if (__result && typeof __result.then === 'function') {
                      __result.then(
                        function(v) { window.webkit.messageHandlers.botguard.postMessage(
                          JSON.stringify({id:__id, type:'result', value: (v === undefined || v === null) ? '' : String(v) })
                        ); },
                        function(e) { window.webkit.messageHandlers.botguard.postMessage(
                          JSON.stringify({id:__id, type:'error', error: (e && e.message) ? e.message : String(e) })
                        ); }
                      );
                    } else {
                      window.webkit.messageHandlers.botguard.postMessage(
                        JSON.stringify({id:__id, type:'result', value: (__result === undefined || __result === null) ? '' : String(__result) })
                      );
                    }
                  } catch(e) {
                    window.webkit.messageHandlers.botguard.postMessage(
                      JSON.stringify({id:__id, type:'error', error: (e && e.message) ? e.message : String(e) })
                    );
                  }
                })();
                """

                await MainActor.run {
                    wv?.evaluateJavaScript(fullJS) { _, error in
                        if error != nil {
                            Task { [weak self] in
                                await self?.resolveContinuation(id, result: .failure(BotGuardError.descrambleFailed))
                            }
                        }
                    }
                }
            }
        }
    }

    private var continuations: [String: CheckedContinuation<String, Error>] = [:]
    private let contQueue = DispatchQueue(label: "potoken.continuations")

    private func setContinuation(_ id: String, _ cont: CheckedContinuation<String, Error>) {
        contQueue.sync { continuations[id] = cont }
    }

    @discardableResult
    private func resolveContinuation(_ id: String, result: Result<String, Error>) -> Bool {
        contQueue.sync {
            let cont = continuations.removeValue(forKey: id)
            switch result {
            case .success(let value): cont?.resume(returning: value)
            case .failure(let error): cont?.resume(throwing: error)
            }
            return cont != nil
        }
    }

    fileprivate func handleMessage(json: [String: Any]) {
        guard let id = json["id"] as? String, let type = json["type"] as? String else { return }

        switch type {
        case "result":
            let value = json["value"] as? String ?? ""
            resolveContinuation(id, result: .success(value))
        case "error":
            let error = json["error"] as? String ?? "Unknown error"
            SwiftyTubeLog.error("JS error: \(error)")
            resolveContinuation(id, result: .failure(BotGuardError.descrambleFailed))
        default:
            break
        }
    }

    // MARK: - Utilities

    private func buildChallengeJSON(_ challenge: BotGuardChallenge) -> String {
        let interpreterJSON: String
        if let js = challenge.interpreterJavascript {
            let escaped = JSEscaping.escape(js)
            interpreterJSON = """
            {"privateDoNotAccessOrElseSafeScriptWrappedValue":"\(escaped)"}
            """
        } else {
            interpreterJSON = "null"
        }

        let hash = challenge.interpreterHash.map(JSEscaping.escape) ?? ""
        let globalName = challenge.globalName.map(JSEscaping.escape) ?? ""
        let program = JSEscaping.escape(challenge.program)
        let messageId = challenge.messageId.map(JSEscaping.escape) ?? ""

        return """
        {
          "messageId": "\(messageId)",
          "interpreterJavascript": \(interpreterJSON),
          "interpreterHash": "\(hash)",
          "program": "\(program)",
          "globalName": "\(globalName)",
          "clientExperimentsStateBlob": ""
        }
        """
    }

    private func u8ToBase64(_ u8string: String) -> String {
        let bytes = u8string
            .split(separator: ",")
            .compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
        return bytes.isEmpty ? u8string : Data(bytes).base64EncodedString()
    }
}

private final class PoTokenMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var generator: PoTokenGenerator?

    init(generator: PoTokenGenerator) {
        self.generator = generator
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "botguard",
              let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        Task { [weak self] in
            await self?.generator?.handleMessage(json: json)
        }
    }
}
