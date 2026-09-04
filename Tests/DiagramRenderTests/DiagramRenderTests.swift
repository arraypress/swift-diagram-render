//
//  DiagramRenderTests.swift
//  DiagramRender
//
//  The engine is bundled and `dot` is optional, so most of this runs with no
//  network and no install. The graphviz tests skip when it is absent rather
//  than failing a machine that simply has not got it.
//

import CoreGraphics
import Foundation
import XCTest
@testable import DiagramRender

final class LanguageTests: XCTestCase {

    func testDOTIsRecognisedByItsOpeningWord() {
        XCTAssertEqual(DiagramLanguage.detect(in: "digraph G { a -> b }"), .graphviz)
        XCTAssertEqual(DiagramLanguage.detect(in: "graph { a -- b }"), .graphviz)
        XCTAssertEqual(DiagramLanguage.detect(in: "strict digraph { a -> b }"), .graphviz)
    }

    func testMermaidIsTheDefault() {
        XCTAssertEqual(DiagramLanguage.detect(in: "flowchart TD\n A --> B"), .mermaid)
        XCTAssertEqual(DiagramLanguage.detect(in: "sequenceDiagram\n a->>b: hi"), .mermaid)
        XCTAssertEqual(DiagramLanguage.detect(in: "gantt\n title x"), .mermaid)
    }

    func testLeadingCommentsAndBlankLinesAreSkipped() {
        // A mermaid file often opens with %%{init}%% or a note, and a DOT
        // file with a // comment; detecting on the literal first line would
        // send both to the wrong engine.
        XCTAssertEqual(DiagramLanguage.detect(in: "\n\n// the graph\ndigraph { a -> b }"), .graphviz)
        XCTAssertEqual(DiagramLanguage.detect(in: "%% a note\nflowchart TD\n A --> B"), .mermaid)
    }
}

final class FormatTests: XCTestCase {

    func testAFormatComesFromTheExtension() {
        XCTAssertEqual(DiagramFormat(path: "/a/b/out.PNG"), .png)
        XCTAssertEqual(DiagramFormat(path: "out.svg"), .svg)
        XCTAssertEqual(DiagramFormat(path: "out.pdf"), .pdf)
        XCTAssertNil(DiagramFormat(path: "out.gif"))
        XCTAssertNil(DiagramFormat(path: "out"))
    }

    func testTheDarkThemeAsksForADarkPage() {
        // Mermaid's dark theme draws light text; on the white a snapshot
        // defaults to, the result is legible only in the sense that the
        // pixels are there.
        XCTAssertTrue(DiagramTheme.dark.wantsDarkBackground)
        XCTAssertFalse(DiagramTheme.default.wantsDarkBackground)
    }
}

@MainActor
final class MermaidTests: XCTestCase {

    private let flow = "flowchart LR\n  A[one] --> B[two] --> C[three]"

    func testTheEngineIsBundled() {
        // Not fetched: the whole point is that this works on a plane.
        XCTAssertNotNil(Mermaid.engine)
        XCTAssertGreaterThan(Mermaid.engine?.count ?? 0, 1_000_000)
    }

    func testItRendersAndSVGComesOutFree() async throws {
        let rendering = try await Mermaid.render(flow)
        XCTAssertTrue(rendering.svg.contains("<svg"))
        XCTAssertGreaterThan(rendering.size.width, 100)
        XCTAssertGreaterThan(rendering.size.height, 10)
        XCTAssertNil(rendering.png, "PNG costs a snapshot and was not asked for")
    }

    func testTheMeasuredSizeIsTheDiagramNotThePage() async throws {
        // Mermaid emits width="100%" with the real size only in the viewBox,
        // so the element measures as whatever its parent gives it. The first
        // version of this reported 300pt wide for every diagram and stretched
        // them all to fit. Two different diagrams must differ in size.
        let small = try await Mermaid.render("flowchart LR\n A --> B")
        let large = try await Mermaid.render(
            "flowchart LR\n A[a very much longer label indeed] --> B --> C --> D --> E")
        XCTAssertGreaterThan(large.size.width, small.size.width * 1.5)
    }

    func testTheScaleIsExactWhateverTheDisplay() async throws {
        // snapshotWidth is in POINTS and arrives on the screen's own backing
        // store, so asking for width × 2 on a Retina Mac produced a 4×
        // image — and 2× on an external 1× display. The bitmap is drawn at an
        // exact pixel size instead, so --scale 2 means 2 everywhere.
        let padding = 10.0, scale = 2.0
        let rendering = try await Mermaid.render(flow, options: .init(
            scale: scale, padding: padding, formats: [.svg, .png]))
        let png = try XCTUnwrap(rendering.png)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertEqual(Double(image.width), (rendering.size.width + padding * 2) * scale, accuracy: 1)
        XCTAssertEqual(Double(image.height), (rendering.size.height + padding * 2) * scale, accuracy: 1)
    }

    func testAPDFIsProducedWhenAskedFor() async throws {
        let rendering = try await Mermaid.render(flow, options: .init(formats: [.svg, .pdf]))
        XCTAssertEqual(rendering.pdf?.prefix(4).map { $0 }, Array("%PDF".utf8))
    }

    func testAThemeChangesTheDrawing() async throws {
        let light = try await Mermaid.render(flow, options: .init(theme: .default))
        let forest = try await Mermaid.render(flow, options: .init(theme: .forest))
        XCTAssertNotEqual(light.svg, forest.svg)
    }

    func testASyntaxErrorCarriesMermaidsOwnMessage() async {
        do {
            _ = try await Mermaid.render("flowchart TD\n  A --> ->> B[[")
            XCTFail("a broken diagram rendered")
        } catch let error as DiagramError {
            guard case let .syntax(message) = error else { return XCTFail("got \(error)") }
            XCTAssertTrue(message.lowercased().contains("expecting") || message.contains("line"), message)
        } catch { XCTFail("got \(error)") }
    }

    func testAnEmptyDiagramIsRefused() async {
        do {
            _ = try await Mermaid.render("   \n  ")
            XCTFail("an empty diagram rendered")
        } catch let error as DiagramError {
            guard case .syntax = error else { return XCTFail("got \(error)") }
        } catch { XCTFail("got \(error)") }
    }

    func testAwkwardCharactersSurviveTheJourneyIntoJavaScript() async throws {
        // A diagram legitimately contains quotes, backslashes and newlines.
        // Interpolating them into the page would end the string literal and
        // turn the caller's diagram into a syntax error in our own script.
        let awkward = "flowchart TD\n  A[\"it's C:\\\\Users\"] --> B[\"a `tick` and a $dollar\"]"
        let rendering = try await Mermaid.render(awkward)
        XCTAssertTrue(rendering.svg.contains("Users"), "the label did not survive")
        XCTAssertTrue(rendering.svg.contains("dollar"), "the second label did not survive")
    }

    func testTheHTMLQuotesTheSourceRatherThanInterpolatingIt() {
        let page = Mermaid.html(source: "A[\"x\"] --> B", engine: "/* engine */", options: .init())
        XCTAssertFalse(page.contains("A[\"x\"] --> B"), "the source was interpolated raw")
        XCTAssertTrue(page.contains("\\\"x\\\""), "the source was not JSON-quoted")
    }
}

@MainActor
final class GraphvizTests: XCTestCase {

    private func requireDot() throws {
        try XCTSkipUnless(Graphviz.isInstalled, "graphviz is not installed")
    }

    func testItRendersDOT() async throws {
        try requireDot()
        let rendering = try Graphviz.render("digraph G { a -> b -> c }", formats: [.svg, .png])
        XCTAssertTrue(rendering.svg.contains("<svg"))
        XCTAssertGreaterThan(rendering.size.width, 10)
        XCTAssertNotNil(rendering.png)
    }

    func testDOTsOwnErrorIsPassedThrough() throws {
        try requireDot()
        // dot names the line; nothing this could invent would be better.
        XCTAssertThrowsError(try Graphviz.render("digraph { a -> }")) { error in
            guard case let DiagramError.syntax(message) = error else { return XCTFail("got \(error)") }
            XCTAssertTrue(message.contains("line"), message)
        }
    }

    func testTheSizeIsReadFromDOTsOwnHeader() {
        // Pure, so it runs without graphviz installed.
        let svg = #"<svg width="404pt" height="98pt" viewBox="0 0 404 98">"#
        XCTAssertEqual(Graphviz.size(ofSVG: svg), CGSize(width: 404, height: 98))
    }

    func testAMissingHeaderFallsBackRatherThanCrashing() {
        XCTAssertEqual(Graphviz.size(ofSVG: "<svg>"), CGSize(width: 800, height: 600))
    }
}

@MainActor
final class WritingTests: XCTestCase {

    func testTheFormatComesFromTheFilename() async throws {
        let rendering = try await Mermaid.render("flowchart LR\n A --> B",
                                                 options: .init(formats: [.svg, .png]))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagram-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Diagram.write(rendering, to: directory.appendingPathComponent("a.svg"))
        try Diagram.write(rendering, to: directory.appendingPathComponent("a.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.svg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.png").path))
    }

    func testAFormatThatWasNotRenderedIsRefusedNotWrittenEmpty() async throws {
        let rendering = try await Mermaid.render("flowchart LR\n A --> B", options: .init(formats: [.svg]))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nope.pdf")
        XCTAssertThrowsError(try Diagram.write(rendering, to: file))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testAnUnknownExtensionIsRefused() async throws {
        let rendering = try await Mermaid.render("flowchart LR\n A --> B")
        XCTAssertThrowsError(try Diagram.write(rendering, to: URL(fileURLWithPath: "/tmp/out.gif")))
    }
}
