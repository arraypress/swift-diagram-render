//
//  DiagramTheme.swift
//  DiagramRender
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

/// What comes out.
public enum DiagramFormat: String, Sendable, Codable, CaseIterable {
    case svg, png, pdf

    public var fileExtension: String { rawValue }

    /// The format for a path, by its extension.
    public init?(path: String) {
        guard let format = DiagramFormat(rawValue: (path as NSString).pathExtension.lowercased()) else {
            return nil
        }
        self = format
    }
}

/// Which language a diagram is written in.
public enum DiagramLanguage: String, Sendable, Codable, CaseIterable {
    case mermaid
    case graphviz

    /// A guess from the source itself.
    ///
    /// Graphviz opens with `digraph`, `graph` or `strict`; mermaid opens with
    /// one of a couple of dozen diagram keywords. Guessing beats making every
    /// caller pass a flag, and a wrong guess fails loudly at parse time
    /// rather than drawing something wrong.
    public static func detect(in source: String) -> DiagramLanguage {
        let first = source
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("%%") && !$0.hasPrefix("//") } ?? ""
        let word = first.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        return ["digraph", "graph", "strict"].contains(word) ? .graphviz : .mermaid
    }
}
