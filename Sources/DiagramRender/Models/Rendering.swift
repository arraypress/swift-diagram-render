//
//  Rendering.swift
//  DiagramRender
//

import CoreGraphics
import Foundation

/// A rendered diagram.
///
/// One render produces all three shapes, because the expensive part is
/// laying the diagram out and every format falls out of the same page.
public struct Rendering: Sendable {

    /// The vector source, always present.
    ///
    /// Free, and worth having: mermaid *produces* SVG, so this needs no SVG
    /// encoder — which is the reason `chart` in this fleet cannot offer one.
    public let svg: String

    /// The diagram's own size in points, as laid out.
    public let size: CGSize

    /// Only present when asked for.
    public let png: Data?
    /// The diagram as a one-page PDF, when it was asked for.
    public let pdf: Data?

    public init(svg: String, size: CGSize, png: Data? = nil, pdf: Data? = nil) {
        self.svg = svg
        self.size = size
        self.png = png
        self.pdf = pdf
    }

    /// The bytes for one format.
    public func data(_ format: DiagramFormat) -> Data? {
        switch format {
        case .svg: return Data(svg.utf8)
        case .png: return png
        case .pdf: return pdf
        }
    }
}
