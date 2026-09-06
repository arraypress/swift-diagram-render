//
//  DiagramTheme.swift
//  DiagramRender
//

//

import Foundation

/// Mermaid's built-in themes.
public enum DiagramTheme: String, Sendable, Codable, CaseIterable {
    case `default`, neutral, dark, forest, base

    /// Whether the theme expects a dark page behind it.
    ///
    /// Mermaid's dark theme draws light text; on the white background a
    /// snapshot defaults to, the result is legible only in the sense that the
    /// pixels are there.
    public var wantsDarkBackground: Bool { self == .dark }
}
