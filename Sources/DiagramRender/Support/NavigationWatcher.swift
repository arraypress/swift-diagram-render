//
//  NavigationWatcher.swift
//  DiagramRender
//
//  Waiting for a page to load without pumping the run loop.
//

import Foundation
@preconcurrency import WebKit

/// Bridges `WKNavigationDelegate` to `async`.
///
/// Awaiting rather than pumping `RunLoop.main`: WebKit delivers its callbacks
/// on the main dispatch queue, and draining that queue from inside a
/// MainActor job is not re-entrant — it hangs. Suspending lets the queue
/// drain and the callbacks arrive.
@MainActor
final class NavigationWatcher: NSObject, WKNavigationDelegate {

    private var continuation: CheckedContinuation<Void, Error>?

    func waitForLoad(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                self.finish(.failure(DiagramError.timedOut(seconds: Int(timeout))))
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finish(.success(())) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
}
