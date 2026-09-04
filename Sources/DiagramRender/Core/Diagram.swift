//
//  Diagram.swift
//  DiagramRender
//
//  One entry point over both engines.
//

import Foundation

/// Rendering a diagram, whichever language it is written in.
@MainActor
public enum Diagram {

    /// Renders mermaid or DOT, detecting which unless told.
    public static func render(
        _ source: String,
        language: DiagramLanguage? = nil,
        options: Mermaid.Options = Mermaid.Options()
    ) async throws -> Rendering {
        switch language ?? DiagramLanguage.detect(in: source) {
        case .mermaid:
            return try await Mermaid.render(source, options: options)
        case .graphviz:
            /// Graphviz ignores theme, scale and padding: it lays out and
            /// paints its own graph, and pretending otherwise would mean
            /// silently dropping flags the caller passed.
            return try Graphviz.render(source, formats: options.formats)
        }
    }

    /// Writes a rendering to a file, choosing the format from the extension.
    public static func write(_ rendering: Rendering, to url: URL) throws {
        guard let format = DiagramFormat(path: url.path) else {
            throw DiagramError.cannotWrite("\(url.lastPathComponent) — name it .svg, .png or .pdf")
        }
        guard let data = rendering.data(format) else {
            throw DiagramError.cannotWrite("\(url.lastPathComponent) — that format was not rendered")
        }
        try data.write(to: url, options: .atomic)
    }
}
