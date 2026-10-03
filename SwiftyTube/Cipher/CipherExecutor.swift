//
//  CipherExecutor.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Cipher calls via the shared WebView, plus one-line provider wiring.
public actor CipherExecutor {
    public static let shared = CipherExecutor()

    private let customWebView: CipherWebView?
    private let fetcher: PlayerJsFetcher

    public init(webView: CipherWebView? = nil, fetcher: PlayerJsFetcher = .shared) {
        self.customWebView = webView
        self.fetcher = fetcher
    }

    public func resolveCipherURL(
        cipherText: String,
        playerJs: String,
        playerHash: String?
    ) async throws -> String {
        _ = playerJs
        _ = playerHash
        let view: CipherWebView
        if let customWebView {
            view = customWebView
        } else {
            view = await CipherWebView.shared
        }
        try await view.load()
        return try await view.resolveCipherURL(cipherText: cipherText)
    }

    public func getSignatureTimestamp() async throws -> Int {
        try await fetcher.getSignatureTimestamp()
    }
}

public extension StreamResolveProviders {
    /// Full cipher wiring for `StreamResolver.resolve`.
    static var live: StreamResolveProviders {
        StreamResolveProviders(
            signatureTimestamp: { try? await PlayerJsFetcher.shared.getSignatureTimestamp() },
            cipherURL: { cipherText, playerJs in
                try await CipherExecutor.shared.resolveCipherURL(
                    cipherText: cipherText,
                    playerJs: playerJs,
                    playerHash: nil
                )
            },
            playerJs: { try await PlayerJsFetcher.shared.getPlayerJs() },
            onStreamRejection: { await PlayerConfigStore.shared.notifyStreamRejection() }
        )
    }
}
