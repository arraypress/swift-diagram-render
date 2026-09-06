//
//  DiagramError.swift
//  DiagramRender
//

import Foundation

/// Why a diagram could not be rendered.
public enum DiagramError: Error, LocalizedError, Equatable {

    /// Mermaid or dot refused the source. The message is theirs.
    case syntax(String)
    /// The render did not finish in time.
    case timedOut(seconds: Int)
    /// The bundled mermaid build is missing.
    case engineMissing
    /// `dot` is not installed.
    case graphvizMissing
    /// The renderer produced nothing.
    case empty
    case cannotWrite(String)

    /// A one-line reason, for a CLI or a log.
    public var errorDescription: String? {
        switch self {
        case let .syntax(message): return message
        case let .timedOut(seconds): return "the diagram did not render within \(seconds) s"
        case .engineMissing: return "the bundled mermaid build is missing from this install"
        case .graphvizMissing: return "graphviz is not installed — run: brew install graphviz"
        case .empty: return "the renderer produced no diagram"
        case let .cannotWrite(path): return "could not write \(path)"
        }
    }
}
