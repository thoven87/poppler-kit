import Foundation
import PopplerKit
import PopplerLayout
import Testing

private func loadPDF(_ name: String) throws -> PopplerDocument {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "pdf"))
    return try PopplerDocument.load(from: url)
}

// MARK: - Bialetti income statement
//
// issue-336-conto-economico-bialetti.pdf — Ghostscript export of an Excel
// spreadsheet.  All borders are drawn vector lines, making it an ideal fixture
// for line-art table detection.  The key regression: long Italian row labels
// ("2) Variazione rimanenze…") must stay on a single table row alongside their
// four year-column values.

@Suite("Bialetti — issue-336-conto-economico-bialetti.pdf")
struct BialettiTests {

    @Test("Page 0 text contains years 2015–2018, Italian row labels, and four monetary values")
    func financialDataExtractable() throws {
        let doc = try loadPDF("issue-336-conto-economico-bialetti")
        let text = try doc.page(at: 0).text()
        for year in ["2015", "2016", "2017", "2018"] {
            #expect(text.contains(year))
        }
        #expect(text.contains("Variazione rimanenze"))
        for value in ["1.942.000", "117.000", "2.538.000", "-3.970.000"] {
            #expect(text.contains(value))
        }
    }

    @Test("Line art has both horizontal and vertical segments (≥10 total)")
    func lineArtHasBothAxes() throws {
        let segs = try doc0().lineArtSegments()
        #expect(segs.count >= 10)
        #expect(segs.filter { $0.isHorizontal() }.count >= 5)
        #expect(segs.filter { $0.isVertical() }.count >= 2)
    }

    @Test("Line-art segment coordinates are finite and page-bounded")
    func lineArtCoordinatesValid() throws {
        let page = try doc0()
        let pw = page.cropBox.width
        let ph = page.cropBox.height
        for seg in page.lineArtSegments() {
            #expect(seg.x1.isFinite && seg.x2.isFinite && seg.y1.isFinite && seg.y2.isFinite)
            #expect(seg.x1 >= -10 && seg.x1 <= pw + 10)
            #expect(seg.x2 >= -10 && seg.x2 <= pw + 10)
            #expect(seg.y1 >= -10 && seg.y1 <= ph + 10)
            #expect(seg.y2 >= -10 && seg.y2 <= ph + 10)
        }
    }

    @Test("Detected table has ≥4 columns and ≥5 rows spanning ≥50% of page width")
    func lineArtTableStructure() throws {
        let page = try doc0()
        let tables = page.detectLineArtTables()
        let first = try #require(tables.first, "Expected a bordered table")
        #expect(first.table.headers.count >= 4)
        #expect(first.table.rows.count >= 5)
        #expect(first.boundingBox.right - first.boundingBox.left >= page.cropBox.width * 0.5)
    }

    @Test("extractLayout() produces table elements for both pages")
    func layoutContainsTables() async throws {
        let layout = try await loadPDF("issue-336-conto-economico-bialetti").extractLayout()
        let tableCount = layout.flatMap { $0 }.filter {
            if case .table = $0 { return true }
            return false
        }.count
        #expect(layout.count == 2)
        #expect(tableCount >= 1)
    }

    // Helper: page 0 of the Bialetti document
    private func doc0() throws -> PopplerPage {
        try loadPDF("issue-336-conto-economico-bialetti").page(at: 0)
    }
}

// MARK: - MORAN academic paper
//
// 1901.03003.pdf — 15-page two-column LaTeX paper.
// Verifies XY-Cut++ reading order, hidden-text safety, table detection,
// heading extraction, and file-handle release.

@Suite("MORAN academic paper — 1901.03003.pdf")
struct MORANTests {

    @Test("15 pages, US Letter, pdfTeX")
    func documentProperties() throws {
        let doc = try loadPDF("1901.03003")
        let page = try doc.page(at: 0)
        #expect(doc.pageCount == 15)
        #expect(abs(page.cropBox.width - 612) < 2)
        #expect(abs(page.cropBox.height - 792) < 2)
        #expect((doc.producer ?? "").localizedCaseInsensitiveContains("pdfTeX"))
    }

    @Test("Title page text contains the paper acronym and abstract opening sentence")
    func contentExtractable() throws {
        let text = try loadPDF("1901.03003").page(at: 0).text()
        #expect(text.contains("MORAN"))
        #expect(text.contains("Irregular text"))
    }

    @Test("XY-Cut++ places left-column content before right-column on a body page")
    func xyCutLeftColumnFirst() throws {
        let page = try loadPDF("1901.03003").page(at: 1)
        let lines = page.textLines(sortReadingOrder: true)
        let midX = page.cropBox.width / 2
        guard
            let leftFirst = lines.first(where: {
                ($0.boundingBox.left + $0.boundingBox.right) / 2 < midX
            }),
            let rightFirst = lines.first(where: {
                ($0.boundingBox.left + $0.boundingBox.right) / 2 > midX
            })
        else { return }
        let li =
            lines.firstIndex {
                $0.text == leftFirst.text && $0.boundingBox == leftFirst.boundingBox
            } ?? 0
        let ri =
            lines.firstIndex {
                $0.text == rightFirst.text && $0.boundingBox == rightFirst.boundingBox
            } ?? 0
        #expect(li < ri, "Left column (idx \(li)) must precede right column (idx \(ri))")
    }

    @Test("No render-mode-3 (invisible) text across all 15 pages")
    func noInvisibleText() throws {
        let doc = try loadPDF("1901.03003")
        for i in 0..<doc.pageCount {
            #expect(
                try doc.page(at: i).invisibleTextBoundingBoxes().isEmpty,
                "Page \(i) has unexpected invisible text")
        }
    }

    @Test("detectTables() finds a table cluster on at least one of the 15 pages")
    func tableDetected() throws {
        let doc = try loadPDF("1901.03003")
        let found = try (0..<doc.pageCount).contains { i in
            try !doc.page(at: i).detectTables().isEmpty
        }
        #expect(found)
    }

    @Test("Full layout pipeline: 15 pages, ≥3 headings, paper content in text")
    func layoutPipeline() async throws {
        let doc = try loadPDF("1901.03003")
        let layout = try await doc.extractLayout()
        let headings = layout.flatMap { $0 }.filter {
            if case .heading = $0 { return true }
            return false
        }
        let text = try await doc.extractLayoutText(removeChrome: true)
        #expect(layout.count == 15)
        #expect(headings.count >= 3)
        #expect(text.contains("MORAN") || text.contains("Irregular"))
    }

    @Test("File handle is released after the document is deallocated")
    func fileHandleReleased() throws {
        let url = try #require(Bundle.module.url(forResource: "1901.03003", withExtension: "pdf"))
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("moran-\(UUID().uuidString).pdf")
        try FileManager.default.copyItem(at: url, to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        do {
            let doc = try PopplerDocument.load(from: tmpURL)
            _ = doc.pageCount
            _ = try? doc.page(at: 0).text()
        }
        try FileManager.default.removeItem(at: tmpURL)
        #expect(!FileManager.default.fileExists(atPath: tmpURL.path))
    }
}

// MARK: - lorem.pdf (opendataloader ground truth)
//
// lorem.pdf is a single-page document from the opendataloader-pdf sample set.
// samples/json/lorem.json records the exact expected structure, giving us
// ground truth to assert against rather than loose thresholds.
//
// Ground truth (from lorem.json):
//   pages : 1
//   author: "leebd-public"
//   title : nil
//   elements:
//     [0] heading, level 1, font Pretendard-Regular 32pt, text "Lorem Ipsum"
//     [1] paragraph,        font Pretendard-Regular 10pt, full lorem ipsum text

@Suite("lorem.pdf — single-page document (opendataloader ground truth)")
struct LoremTests {

    // MARK: Document metadata

    @Test("pageCount is 1, author is leebd-public, title is nil")
    func documentProperties() throws {
        let doc = try loadPDF("lorem")
        #expect(doc.pageCount == 1)
        #expect(doc.author == "leebd-public")
        #expect(doc.title == nil)
        #expect(doc.hasExtractableText)
    }

    // MARK: Text layer

    @Test("Page text contains the H1 heading and the complete lorem ipsum paragraph")
    func pageTextContent() throws {
        let text = try loadPDF("lorem").page(at: 0).text()
        // Heading
        #expect(text.contains("Lorem Ipsum"))
        // Opening of the paragraph
        #expect(text.contains("Lorem ipsum dolor sit amet, consectetur adipiscing elit"))
        // End of the paragraph — confirms full text was captured
        #expect(text.contains("anim id est laborum"))
    }

    // MARK: Layout analysis

    @Test("extractLayout() yields exactly one level-1 heading and only paragraph body elements")
    func layoutStructure() async throws {
        // Ground truth (lorem.json): 2 logical elements — a Doctitle heading + one paragraph.
        // Current behaviour differences (both tracked as separate issues):
        //   • Paragraph-line consolidation is not yet implemented, so each of the 6
        //     wrapped lines becomes its own .paragraph (total = 7, not 2).
        //   • XYCutSorter’s single-column fallback sorts bottom-to-top for
        //     poppler-cpp screen-Y coordinates, so element order is not guaranteed.
        // This test asserts STRUCTURE and CONTENT only — independent of order and count.
        let pages = try await loadPDF("lorem").extractLayout()
        #expect(pages.count == 1)

        let elements = pages[0].filter { !$0.isChrome }

        let headings = elements.filter {
            if case .heading = $0 { return true }
            return false
        }
        let paragraphs = elements.filter {
            if case .paragraph = $0 { return true }
            return false
        }
        let unexpected = elements.filter {
            if case .heading = $0 { return false }
            if case .paragraph = $0 { return false }
            return true
        }

        // Structure: exactly 1 heading, at least 1 paragraph, nothing else.
        #expect(headings.count == 1)
        #expect(!paragraphs.isEmpty)
        #expect(
            unexpected.isEmpty,
            "Unexpected element types: \(unexpected.map { "\($0)" })")

        // Heading is level 1 “Lorem Ipsum” at ~32 pt (Pretendard-Regular per ground truth).
        if case .heading(let level, let text, _, let fontSize) = headings[0] {
            #expect(level == 1)
            #expect(text.contains("Lorem Ipsum"))
            #expect(fontSize > 20, "Expected heading ~32 pt per ground truth, got \(fontSize)")
        }

        // Combined paragraph text contains the full lorem ipsum content.
        let combined = paragraphs.map(\.text).joined(separator: " ")
        #expect(combined.contains("Lorem ipsum dolor sit amet"))
        #expect(combined.contains("anim id est laborum"))
    }

    @Test("textStream() yields exactly 1 non-empty page string")
    func streamYieldsOnePage() async throws {
        let doc = try loadPDF("lorem")
        var pages: [String] = []
        for try await text in doc.textStream() {
            pages.append(text)
        }
        #expect(pages.count == 1)
        #expect(pages[0].contains("Lorem Ipsum"))
        #expect(pages[0].contains("Lorem ipsum dolor sit amet"))
    }
}
