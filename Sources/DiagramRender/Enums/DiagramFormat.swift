//
//  DiagramFormat.swift
//  DiagramRender
//

//

import Foundation

/// What comes out.
public enum DiagramFormat: String, Sendable, Codable, CaseIterable {
    case svg, png, pdf

    /// The extension a file of this format takes, without the dot.
    public var fileExtension: String { rawValue }

    /// The format for a path, by its extension.
    public init?(path: String) {
        guard let format = DiagramFormat(rawValue: (path as NSString).pathExtension.lowercased()) else {
            return nil
        }
        self = format
    }
}
