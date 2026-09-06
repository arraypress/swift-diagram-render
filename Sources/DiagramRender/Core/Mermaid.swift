//
//  Mermaid.swift
//  DiagramRender
//
//  Mermaid, rendered on this machine — no service, no network, no node.
//

import AppKit
import CoreGraphics
import Foundation
@preconcurrency import WebKit

/// Renders mermaid diagrams.
///
/// Mermaid is JavaScript, so this drives a headless `WKWebView`: the engine
/// is bundled (3.4 MB, MIT), the page is a local file, and nothing is
/// fetched. The same approach `pdf html` already uses in this fleet.
///
/// **SVG comes out for free**, which is the point. Mermaid *produces* SVG, so
/// no SVG encoder is needed — the thing Apple does not ship, and the reason
/// `chart` in this fleet can only offer PNG and PDF.
@MainActor
public enum Mermaid {

    /// How to render.
    public struct Options: Sendable {
        /// Which palette the diagram is drawn in.
        public var theme: DiagramTheme
        /// Pixel density for PNG. 2 gives a Retina-sized image.
        public var scale: Double
        /// A CSS colour, or nil for transparent.
        public var background: String?
        /// Blank space around the diagram, in points.
        public var padding: Double
        /// Seconds before an unfinished render is abandoned.
        public var timeout: TimeInterval
        /// Which shapes to produce. SVG is always produced; the others cost
        /// a snapshot each.
        public var formats: Set<DiagramFormat>

        public init(theme: DiagramTheme = .default, scale: Double = 2,
                    background: String? = "white", padding: Double = 16,
                    timeout: TimeInterval = 30,
                    formats: Set<DiagramFormat> = [.svg]) {
            self.theme = theme
            self.scale = scale
            self.background = background
            self.padding = padding
            self.timeout = timeout
            self.formats = formats
        }
    }

    /// The bundled mermaid build.
    static var engine: String? {
        guard let url = Bundle.module.url(forResource: "mermaid.min", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Renders one diagram.
    public static func render(_ source: String, options: Options = Options()) async throws -> Rendering {
        guard let engine else { throw DiagramError.engineMissing }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DiagramError.syntax("the diagram is empty") }

        /// A window materialises enough AppKit for WebKit to lay out. Without
        /// it the view has no backing store and every snapshot comes back
        /// blank — which looks like a diagram that rendered to nothing.
        _ = NSApplication.shared

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagram-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let page = directory.appendingPathComponent("diagram.html")
        try html(source: trimmed, engine: engine, options: options).write(to: page, atomically: true, encoding: .utf8)

        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1400, height: 1000))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        if options.background == nil {
            /// Undocumented but long-standing, and the only way to snapshot a
            /// page without WebKit painting its own white behind it.
            view.setValue(false, forKey: "drawsBackground")
        }

        let watcher = NavigationWatcher()
        view.navigationDelegate = watcher
        view.loadFileURL(page, allowingReadAccessTo: directory)
        try await watcher.waitForLoad(timeout: options.timeout)

        try await settle(view, timeout: options.timeout)

        if let message = try? await view.evaluateJavaScript("window.__error"), !(message is NSNull),
           let text = message as? String {
            throw DiagramError.syntax(clean(text))
        }

        let svg = try await view.evaluateJavaScript(
            "(() => { const s = document.querySelector('#out svg'); return s ? s.outerHTML : ''; })()"
        ) as? String ?? ""
        guard !svg.isEmpty else { throw DiagramError.empty }

        let measured = try await view.evaluateJavaScript(
            "(() => { const r = document.querySelector('#out svg').getBoundingClientRect(); return [r.width, r.height]; })()"
        ) as? [Double] ?? []
        let size = CGSize(width: (measured.first ?? 800).rounded(.up),
                          height: (measured.last ?? 600).rounded(.up))

        guard options.formats.contains(.png) || options.formats.contains(.pdf) else {
            return Rendering(svg: svg, size: size)
        }

        /// Resized to the diagram plus its padding before snapshotting, so
        /// the image is the diagram rather than the diagram in the corner of
        /// a 1400-point page.
        let frame = CGSize(width: size.width + options.padding * 2,
                           height: size.height + options.padding * 2)
        view.frame = CGRect(origin: .zero, size: frame)
        window.setContentSize(frame)
        try? await Task.sleep(nanoseconds: 250_000_000)

        var png: Data?
        if options.formats.contains(.png) {
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(origin: .zero, size: frame)
            let snapshot = try await view.takeSnapshot(configuration: configuration)
            png = try Self.png(from: snapshot,
                               pixels: CGSize(width: (frame.width * options.scale).rounded(),
                                              height: (frame.height * options.scale).rounded()),
                               opaque: options.background != nil)
        }
        var pdf: Data?
        if options.formats.contains(.pdf) {
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(origin: .zero, size: frame)
            pdf = try await view.pdf(configuration: configuration)
        }
        return Rendering(svg: svg, size: size, png: png, pdf: pdf)
    }

    // MARK: - The page

    static func html(source: String, engine: String, options: Options) -> String {
        /// Through JSON rather than interpolated: a diagram legitimately
        /// contains quotes, backslashes and newlines, and one of them ending
        /// the string literal turns a syntax error in the caller's diagram
        /// into a syntax error in this file's JavaScript.
        let quoted = String(
            data: (try? JSONSerialization.data(withJSONObject: [source])) ?? Data("[\"\"]".utf8),
            encoding: .utf8) ?? "[\"\"]"
        let background = options.background.map { "background:\($0);" } ?? "background:transparent;"

        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          html,body{margin:0;padding:\(options.padding)px;\(background)}
          #out{display:inline-block;line-height:0}
          #out svg{display:block;max-width:none!important}
        </style>
        <script>\(engine)</script>
        </head><body><div id="out"></div>
        <script>
        window.__done = false; window.__error = null;
        (async () => {
          try {
            const engine = (typeof mermaid !== 'undefined') ? mermaid : window.mermaid;
            if (!engine) { window.__error = 'the bundled mermaid build did not load'; window.__done = true; return; }
            engine.initialize({ startOnLoad: false, theme: '\(options.theme.rawValue)' });
            const result = await engine.render('diagram', \(quoted)[0]);
            const host = document.getElementById('out');
            host.innerHTML = result.svg;

            // Mermaid emits width="100%" with the real size only in the
            // viewBox, so the element measures as whatever its parent gives
            // it — which is how the first version of this reported 300pt
            // wide for every diagram and stretched them all to fit.
            const svg = host.querySelector('svg');
            const box = (svg.getAttribute('viewBox') || '').split(/[\\s,]+/).map(Number);
            if (box.length === 4 && box[2] > 0 && box[3] > 0) {
              svg.setAttribute('width', box[2]);
              svg.setAttribute('height', box[3]);
              svg.style.width = box[2] + 'px';
              svg.style.height = box[3] + 'px';
            }
            window.__done = true;
          } catch (error) {
            window.__error = (error && error.message) ? error.message : String(error);
            window.__done = true;
          }
        })();
        </script></body></html>
        """
    }

    /// Waits for the render, polling rather than sleeping a fixed time.
    ///
    /// A fixed sleep is either too short for a large diagram or wasted on a
    /// small one, and mermaid's own render is asynchronous.
    private static func settle(_ view: WKWebView, timeout: TimeInterval) async throws {
        var waited = 0.0
        while waited < timeout {
            if let done = try? await view.evaluateJavaScript("window.__done") as? Bool, done { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 0.05
        }
        throw DiagramError.timedOut(seconds: Int(timeout))
    }

    /// Mermaid prefixes its parse errors with boilerplate a caller cannot act
    /// on; the line and the reason are what matter.
    static func clean(_ message: String) -> String {
        message
            .replacingOccurrences(of: "Parse error on line", with: "line")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Redraws the snapshot at an exact pixel size.
    ///
    /// `snapshotWidth` is measured in POINTS and the snapshot arrives on the
    /// screen's own backing store, so asking for `width × 2` on a Retina Mac
    /// produced a 4× image — measured, and the same code would give 2× on an
    /// external 1× display. Drawing into a bitmap of the wanted pixel size
    /// makes `--scale 2` mean 2 whatever the machine is plugged into.
    private static func png(from image: NSImage, pixels: CGSize, opaque: Bool) throws -> Data {
        guard pixels.width >= 1, pixels.height >= 1,
              let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw DiagramError.empty
        }
        representation.size = pixels

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            throw DiagramError.empty
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        if opaque {
            /// The snapshot of an opaque page is already opaque; this only
            /// matters for the transparent case, where the fresh bitmap
            /// starts as zeroed — that is, clear — which is what we want.
        }
        image.draw(in: CGRect(origin: .zero, size: pixels),
                   from: CGRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1)
        context.flushGraphics()

        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw DiagramError.empty
        }
        return data
    }
}
