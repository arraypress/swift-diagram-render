//
//  DiagramLanguage.swift
//  DiagramRender
//

//

import Foundation

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
