//
//  Graphviz.swift
//  DiagramRender
//
//  The other half, when `dot` is installed.
//

import CoreGraphics
import Foundation

/// Renders DOT graphs through graphviz.
///
/// Graphviz is a C program, not a library this can embed, so `dot` has to be
/// on the machine. That is a soft dependency on purpose: the mermaid half
/// needs nothing at all, and a missing `dot` names the command that fixes it
/// rather than failing obscurely.
public enum Graphviz {

    /// The usual places, plus whatever `PATH` says.
    ///
    /// Looked up rather than hard-coded: Homebrew is at `/opt/homebrew` on
    /// Apple silicon and `/usr/local` on Intel, and a formula-installed tool
    /// runs with a `PATH` its author did not choose.
    public static var executable: URL? {
        let candidates = ["/opt/homebrew/bin/dot", "/usr/local/bin/dot", "/usr/bin/dot"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/dot"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// Whether graphviz is available.
    public static var isInstalled: Bool { executable != nil }

    /// The installed version, for a `describe`-style report.
    public static func version() -> String? {
        guard let output = try? run(["-V"], input: nil) else { return nil }
        /// `dot -V` writes to stderr, which `run` folds in.
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Renders DOT source.
    ///
    /// SVG is always produced — it is what carries the size — and PNG and PDF
    /// each cost another `dot` run, since the program writes one format per
    /// invocation.
    public static func render(_ source: String, formats: Set<DiagramFormat> = [.svg]) throws -> Rendering {
        guard isInstalled else { throw DiagramError.graphvizMissing }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DiagramError.syntax("the diagram is empty") }

        let svg = try output(of: "svg", source: trimmed)
        let text = String(decoding: svg, as: UTF8.self)
        guard !text.isEmpty else { throw DiagramError.empty }

        return Rendering(
            svg: text,
            size: size(ofSVG: text),
            png: formats.contains(.png) ? try output(of: "png", source: trimmed) : nil,
            pdf: formats.contains(.pdf) ? try output(of: "pdf", source: trimmed) : nil)
    }

    private static func output(of format: String, source: String) throws -> Data {
        let result = try run(["-T\(format)"], input: Data(source.utf8))
        guard result.status == 0 else {
            /// dot's own message, which names the line — better than anything
            /// this could invent.
            throw DiagramError.syntax(result.text
                .replacingOccurrences(of: "<stdin>: ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.data
    }

    /// dot writes the size in points on the root `<svg>`.
    static func size(ofSVG text: String) -> CGSize {
        func points(_ attribute: String) -> Double? {
            guard let range = text.range(of: "\(attribute)=\"") else { return nil }
            let rest = text[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return Double(rest[..<end].replacingOccurrences(of: "pt", with: ""))
        }
        return CGSize(width: points("width") ?? 800, height: points("height") ?? 600)
    }

    private static func run(_ arguments: [String], input: Data?) throws -> (data: Data, text: String, status: Int32) {
        guard let executable else { throw DiagramError.graphvizMissing }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        if input != nil {
            let stdin = Pipe()
            process.standardInput = stdin
            try process.run()
            stdin.fileHandleForWriting.write(input!)
            stdin.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errors = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        /// Both streams: `dot -V` reports on stderr and errors go there too,
        /// so a caller reading only stdout learns nothing about either.
        let text = String(decoding: errors.isEmpty ? data : errors, as: UTF8.self)
        return (data, text, process.terminationStatus)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
