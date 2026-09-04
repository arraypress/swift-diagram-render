# Swift DiagramRender

Mermaid and Graphviz, rendered on this machine.

```swift
import DiagramRender

let rendering = try await Diagram.render("""
    flowchart LR
      A[markdown] --> B(diagram) --> C[PNG]
    """, options: .init(formats: [.svg, .png, .pdf]))

rendering.svg      // the vector source, always
rendering.size     // the diagram's own size, in points
try Diagram.write(rendering, to: out)   // format from the extension
```

No service, no key, no network, no Node. Mermaid's engine is bundled (3.4 MB,
MIT); Graphviz uses `dot` if it is installed and says so plainly if it is not.

## SVG comes out free

Mermaid *produces* SVG, so nothing here needs an SVG encoder — the thing Apple
does not ship, and the reason `chart` in this fleet can only offer PNG and PDF.
One render gives all three shapes, because the expensive part is the layout and
every format falls out of the same page.

## How it works

Mermaid is JavaScript, so this drives a headless `WKWebView` from a local file,
the same approach `pdf html` already uses. Awaiting rather than pumping
`RunLoop.main`: WebKit delivers on the main queue, and draining that queue from
inside a MainActor job is not re-entrant.

## Two things measured, not assumed

**Mermaid emits `width="100%"`** with the real size only in the `viewBox`, so
the element measures as whatever its parent gives it. The first version of this
reported 300 pt wide for *every* diagram and stretched them all to fit. The SVG
is now sized from its own viewBox before anything is measured.

**`snapshotWidth` is in points, and the snapshot arrives on the screen's
backing store.** Asking for `width × 2` on a Retina Mac gave a **4×** image —
and would give 2× on an external 1× display. The bitmap is drawn at an exact
pixel size instead, so `scale: 2` means 2 whatever the machine is plugged into.
A test pins `png pixels == (size + 2 × padding) × scale`.

## Graphviz

A soft dependency on purpose: the mermaid half needs nothing at all, and a
missing `dot` reports the command that installs it rather than failing
obscurely. `dot` writes one format per run, so PNG and PDF each cost another
invocation. Its own syntax errors are passed through untouched — they name the
line, and nothing this could invent would be better.

Graphviz ignores theme, scale and padding. It lays out and paints its own
graph, and pretending otherwise would mean silently dropping flags the caller
passed.

## Which language

Detected from the source: DOT opens with `digraph`, `graph` or `strict`,
everything else is mermaid. Leading comments and blank lines are skipped —
a mermaid file often opens with `%%{init}%%` and a DOT file with `//`.

## Tested

22 tests: language detection past comments, the viewBox sizing (two diagrams
of different sizes must measure differently), the exact pixel scale, PDF magic
bytes, mermaid's own error text surviving, a diagram full of quotes,
backslashes and dollar signs reaching the page intact, and a format that was
not rendered being refused rather than written empty. The graphviz tests skip
when `dot` is absent rather than failing a machine that has not got it.

## Licence

MIT. The bundled mermaid build is [mermaid](https://github.com/mermaid-js/mermaid),
also MIT, © Knut Sveidqvist — its licence ships beside it.
