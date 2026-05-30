import Foundation
import PopplerKit
import PopplerLayout
import Testing

// ─────────────────────────────────────────────────────────────────────────────
// chinese_scan.pdf — image-only scanned document
//
// Producer: ReportLab PDF Library
// Pages:    1  ·  A4  ·  PDF 1.3  ·  ~245 KB
//
// A "scanned" PDF: the page contains a rasterised image of Chinese text with
// no embedded text layer.  All text-extraction APIs return empty results.
//
// These tests exercise the zero-text-layer code path:
//   • `hasExtractableText` returns false
//   • text extraction returns empty or whitespace-only strings
//   • rendering succeeds (the image IS present)
//   • all PopplerLayout pipeline steps degrade gracefully to empty output
// ─────────────────────────────────────────────────────────────────────────────

@Suite("chinese_scan.pdf — image-only scanned document")
struct ChineseScanTests {

    private func load() throws -> PopplerDocument {
        let url = try #require(Bundle.module.url(forResource: "chinese_scan", withExtension: "pdf"))
        return try PopplerDocument.load(from: url)
    }

    // MARK: - Basic document properties

    @Test("Loads without error: 1 page, A4, PDF 1.3")
    func basicProperties() throws {
        let doc = try load()
        #expect(doc.pageCount == 1)
        let page = try doc.page(at: 0)
        #expect(abs(page.cropBox.width - 595) < 2)
        #expect(abs(page.cropBox.height - 842) < 2)
        #expect(doc.pdfVersion.major == 1)
        #expect(doc.pdfVersion.minor == 3)
    }

    // MARK: - Text extraction (core behaviour on image-only PDF)

    @Test("hasExtractableText returns false — no text layer")
    func noExtractableText() throws {
        let doc = try load()
        // The whole point of this PDF: it is image-only.
        // hasExtractableText samples up to 5 pages; all will be blank.
        #expect(
            !doc.hasExtractableText,
            "Image-only PDFs should report no extractable text")
    }

    @Test("page.text() returns empty or whitespace-only string")
    func pageTextEmpty() throws {
        let doc = try load()
        let page = try doc.page(at: 0)
        let text = page.text().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(
            text.isEmpty,
            "Expected empty text from image-only page, got: \(text.prefix(50))")
    }

    @Test("textBoxes() returns no boxes")
    func textBoxesEmpty() throws {
        let doc = try load()
        let page = try doc.page(at: 0)
        let boxes = page.textBoxes()
        #expect(
            boxes.isEmpty,
            "Expected no text boxes from image-only page, got \(boxes.count)")
    }

    @Test("search() finds nothing in an image-only page")
    func searchFindsNothing() throws {
        let doc = try load()
        let page = try doc.page(at: 0)
        // Any text search on an image-only page must return empty
        #expect(page.search(for: "的").isEmpty)  // common Chinese character
        #expect(page.search(for: "the").isEmpty)
    }

    // MARK: - Rendering (the image IS there)

    @Test("Page renders to a valid non-empty pixel buffer")
    func pageRenders() throws {
        let doc = try load()
        let page = try doc.page(at: 0)
        let renderer = PopplerRenderer()
        let image = renderer.render(page: page, xres: 36, yres: 36)  // low-res for speed
        let img = try #require(image, "render() should succeed for an image-only PDF")
        #expect(img.width > 0)
        #expect(img.height > 0)
        #expect(!img.data.isEmpty)
    }

    @Test("renderToData() produces a non-empty PNG")
    func renderToDataProducesPNG() throws {
        let doc = try load()
        let page = try doc.page(at: 0)
        let renderer = PopplerRenderer()
        let data = renderer.renderToData(page: page, xres: 36, yres: 36, format: .png)
        let d = try #require(data, "renderToData() should return PNG data")
        // PNG magic bytes: 0x89 50 4E 47
        #expect(d.count > 0)
        #expect(d.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    // MARK: - Line art & invisible text (should both be empty)

    @Test("lineArtSegments() returns empty — no vector drawing operators")
    func lineArtEmpty() throws {
        let doc = try load()
        let page = try doc.page(at: 0)
        let segs = page.lineArtSegments()
        // A scanned image PDF draws content via XObject, not path operators
        #expect(
            segs.isEmpty,
            "Expected no line-art segments from image-only page, got \(segs.count)")
    }

    // MARK: - PopplerLayout pipeline (empty-content robustness)

    @Test("textLines() returns empty array")
    func textLinesEmpty() throws {
        let doc = try load()
        let page = try doc.page(at: 0)
        let lines = page.textLines()
        #expect(
            lines.isEmpty,
            "Expected no visual lines from image-only page, got \(lines.count)")
    }

    @Test("detectTables() returns empty — nothing to cluster")
    func detectTablesEmpty() throws {
        let doc = try load()
        let page = try doc.page(at: 0)
        #expect(page.detectTables().isEmpty)
    }

    @Test("detectLineArtTables() returns empty — no line art")
    func detectLineArtTablesEmpty() throws {
        let doc = try load()
        let page = try doc.page(at: 0)
        #expect(page.detectLineArtTables().isEmpty)
    }

    @Test("extractLayout() returns 1 page of elements without crashing")
    func extractLayoutNoCrash() async throws {
        let doc = try load()
        let layout = try await doc.extractLayout()
        #expect(layout.count == 1)
        // May be empty (no text elements to classify) — that is correct behaviour
        // for an image-only PDF without an image-element type in PopplerLayoutElement
        _ = layout[0].count
    }

    @Test("extractLayoutText() returns empty string for image-only document")
    func extractLayoutTextEmpty() async throws {
        let doc = try load()
        let text = try await doc.extractLayoutText(removeChrome: true)
        #expect(
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Image-only PDF should produce no layout text, got: \(text.prefix(50))")
    }

    // MARK: - Streaming (robustness)

    @Test("textStream() yields no pages (all pages are blank)")
    func textStreamYieldsNothing() async throws {
        let doc = try load()
        var pageCount = 0
        for try await _ in doc.textStream() {
            pageCount += 1
        }
        #expect(
            pageCount == 0,
            "textStream() should skip blank image-only pages; got \(pageCount)")
    }

    @Test("rasterStream() yields exactly 1 image (the rendered page)")
    func rasterStreamYieldsOneImage() async throws {
        let doc = try load()
        var images = [Data]()
        for try await data in doc.rasterStream(xres: 36, yres: 36) {
            images.append(data)
        }
        #expect(
            images.count == 1,
            "Expected 1 rasterised page, got \(images.count)")
        #expect(!images[0].isEmpty)
    }
}
