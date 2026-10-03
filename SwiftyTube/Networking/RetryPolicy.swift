//
//  RetryPolicy.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

/// Exponential backoff with jitter. First retry waits `baseDelay`.
public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: Duration
    public var factor: Double
    public var maxDelay: Duration
    public var jitter: Duration

    public init(
        maxAttempts: Int,
        baseDelay: Duration,
        factor: Double,
        maxDelay: Duration,
        jitter: Duration
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.factor = factor
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    public static let innerTube = RetryPolicy(
        maxAttempts: 3,
        baseDelay: .milliseconds(500),
        factor: 2,
        maxDelay: .seconds(30),
        jitter: .milliseconds(200)
    )

    public func delay(for attempt: Int) -> Duration {
        let exponential = baseDelay * pow(factor, Double(max(attempt, 0)))
        let capped = min(exponential, maxDelay)
        return capped + .milliseconds(Int.random(in: 0 ... jitterMilliseconds))
    }

    public func run<T>(
        _ operation: @Sendable () async throws -> T,
        isRetryable: @Sendable (Error) -> Bool,
        onRetry: (@Sendable (Int, Error) -> Void)? = nil
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0 ..< maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts - 1, isRetryable(error) else { break }
                onRetry?(attempt, error)
                try? await Task.sleep(for: delay(for: attempt))
            }
        }
        throw lastError ?? RetryError.exhausted
    }

    private var jitterMilliseconds: Int {
        let parts = jitter.components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}

public enum RetryError: Error, Sendable, Equatable {
    /// The policy allowed zero attempts, so nothing ran.
    case exhausted
}
