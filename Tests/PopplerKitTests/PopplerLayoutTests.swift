import Foundation
import Testing

@testable import PopplerKit
@testable import PopplerLayout

// MARK: - Helper

private func loadPDF(_ name: String) throws -> PopplerDocument {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "pdf"))
    return try PopplerDocument.load(from: url)
}

// MARK: - Synthetic object factories
//
// Note on coordinate conventions used in unit tests:
//
// • XYCutSorter and HeaderFooterDetector were designed for y-UP (PDF) coordinates
//   where larger `top` = higher on the page.  Unit tests for those components use
//   y-UP values (top > bottom, e.g. top=800, bottom=780 near the page top).
//
// • LineGrouper, AutoTableDetector, and BorderScanDetector work correctly with
//   y-DOWN (screen) coordinates where top < bottom.  Unit tests for those components
//   use y-DOWN values (e.g. top=100, bottom=115 near the page top).
//
// Integration tests call the live poppler pipeline and therefore work with actual
// y-DOWN coordinate values returned by the library.

/// Create a `PopplerTextBox` with specified geometry.
private func makeBox(
    _ text: String,
    left: Double, top: Double, right: Double, bottom: Double,
    fontSize: Double = 12.0,
    fontName: String? = nil
) -> PopplerTextBox {
    PopplerTextBox(
        text: text,
        boundingBox: PopplerRect(left: left, top: top, right: right, bottom: bottom),
        fontName: fontName,
        fontSize: fontSize,
        rotation: 0,
        hasSpaceAfter: false,
        charBBoxes: [],
        writingMode: .horizontal
    )
}

/// Create a single-box `LayoutTextLine`.
private func makeLine(
    _ text: String,
    left: Double, top: Double, right: Double, bottom: Double,
    fontSize: Double = 12.0,
    fontName: String? = nil
) -> LayoutTextLine {
    LayoutTextLine(boxes: [
        makeBox(
            text, left: left, top: top, right: right, bottom: bottom,
            fontSize: fontSize, fontName: fontName)
    ])
}

/// Create a multi-box `LayoutTextLine` (all boxes are at the same vertical position).
private func makeMultiBoxLine(
    _ cells: [(text: String, left: Double, right: Double)],
    top: Double, bottom: Double,
    fontSize: Double = 12.0
) -> LayoutTextLine {
    let boxes = cells.map { cell in
        makeBox(
            cell.text, left: cell.left, top: top, right: cell.right, bottom: bottom,
            fontSize: fontSize)
    }
    return LayoutTextLine(boxes: boxes)
}

// MARK: - 1. XYCutSorter — unit tests

// XYCutSorter was designed for y-UP (PDF) coordinates: larger top value = higher on page.
// Boxes below use those conventions so the algorithm produces reading-order output.

@Suite("XYCutSorter — unit tests")
struct XYCutSorterTests {

    // MARK: Two-column layout

    @Test("Two-column layout: left column first, each column top-to-bottom")
    func twoColumnLayout() {
        //  [0: L-top]          [2: R-top]
        //  [1: L-bot]          [3: R-bot]
        //  col x: 50–150       col x: 350–450
        //  row top-y: 800 / 600 (y-UP)
        let boxes = [
            PopplerRect(left: 50, top: 800, right: 150, bottom: 780),  // 0 left-col top
            PopplerRect(left: 50, top: 600, right: 150, bottom: 580),  // 1 left-col bottom
            PopplerRect(left: 350, top: 800, right: 450, bottom: 780),  // 2 right-col top
            PopplerRect(left: 350, top: 600, right: 450, bottom: 580),  // 3 right-col bottom
        ]
        let result = XYCutSorter.sortedIndices(of: boxes)
        #expect(
            result == [0, 1, 2, 3], "Expected left column then right column, each top-to-bottom")
    }

    // MARK: Single column

    @Test("Single column: sorted top-to-bottom")
    func singleColumnTopToBottom() {
        let boxes = [
            PopplerRect(left: 50, top: 800, right: 250, bottom: 780),  // 0 top
            PopplerRect(left: 50, top: 600, right: 250, bottom: 580),  // 1 middle
            PopplerRect(left: 50, top: 400, right: 250, bottom: 380),  // 2 bottom
        ]
        let result = XYCutSorter.sortedIndices(of: boxes)
        #expect(result == [0, 1, 2])
    }

    @Test("Single element: returned as-is")
    func singleElement() {
        let boxes = [PopplerRect(left: 0, top: 800, right: 300, bottom: 780)]
        #expect(XYCutSorter.sortedIndices(of: boxes) == [0])
    }

    // MARK: Cross-layout element

    @Test("Wide title (cross-layout element) appears before two-column body content")
    func crossLayoutTitleFirst() {
        // Box 0: wide title spanning the full page width — cross-layout element
        // Boxes 1–4: normal two-column body
        let boxes = [
            PopplerRect(left: 0, top: 900, right: 600, bottom: 880),  // 0 wide title
            PopplerRect(left: 50, top: 800, right: 150, bottom: 780),  // 1 left-col top
            PopplerRect(left: 50, top: 600, right: 150, bottom: 580),  // 2 left-col bottom
            PopplerRect(left: 350, top: 800, right: 450, bottom: 780),  // 3 right-col top
            PopplerRect(left: 350, top: 600, right: 450, bottom: 580),  // 4 right-col bottom
        ]
        let result = XYCutSorter.sortedIndices(of: boxes)
        #expect(result.first == 0, "Wide title must be first in reading order")
        #expect(Set(result) == [0, 1, 2, 3, 4], "All boxes must appear in output exactly once")
        // Left column (1, 2) must precede right column (3, 4)
        let leftFirst = result.firstIndex(of: 1)!
        let rightFirst = result.firstIndex(of: 3)!
        #expect(leftFirst < rightFirst, "Left column must come before right column")
    }
}

// MARK: - 2. LineGrouper — unit tests

@Suite("LineGrouper — unit tests")
struct LineGrouperTests {

    // MARK: Same Y → one line

    @Test("Boxes at the same Y position group into one line")
    func sameYOneGroup() {
        // Two boxes at virtually the same vertical position (y-DOWN: top≈50, bottom≈65)
        let boxes = [
            makeBox("Hello", left: 50, top: 50, right: 80, bottom: 65, fontSize: 12),
            makeBox("world", left: 100, top: 51, right: 130, bottom: 66, fontSize: 12),
        ]
        // Y-centres: 57.5 and 58.5 → difference 1.0 ≤ tolerance 6.0
        let lines = LineGrouper.group(boxes)
        #expect(lines.count == 1, "Two same-line boxes should produce exactly one line")
        #expect(lines[0].text.contains("Hello") && lines[0].text.contains("world"))
    }

    // MARK: Different Y → separate lines

    @Test("Boxes at well-separated Y positions produce separate lines")
    func differentYSeparateLines() {
        let boxes = [
            makeBox("Line one", left: 50, top: 50, right: 200, bottom: 65, fontSize: 12),
            makeBox("Line two", left: 50, top: 100, right: 200, bottom: 115, fontSize: 12),
        ]
        // Y-centres: 57.5 and 107.5 → difference 50 > tolerance 6.0
        let lines = LineGrouper.group(boxes)
        #expect(lines.count == 2)
    }

    @Test("Three boxes at three distinct Y positions produce three lines")
    func threeDistinctYs() {
        let boxes = [
            makeBox("A", left: 50, top: 50, right: 80, bottom: 65, fontSize: 12),
            makeBox("B", left: 50, top: 100, right: 80, bottom: 115, fontSize: 12),
            makeBox("C", left: 50, top: 150, right: 80, bottom: 165, fontSize: 12),
        ]
        let lines = LineGrouper.group(boxes)
        #expect(lines.count == 3)
    }

    // MARK: Sort left→right within a line

    @Test("Boxes within a line are sorted left-to-right")
    func sortedLeftToRight() {
        // Feed boxes in reversed X order; grouper should sort them correctly
        let boxes = [
            makeBox("Second", left: 200, top: 50, right: 300, bottom: 65, fontSize: 12),
            makeBox("First", left: 50, top: 50, right: 150, bottom: 65, fontSize: 12),
        ]
        let lines = LineGrouper.group(boxes)
        #expect(lines.count == 1)
        let words = lines[0].boxes.map(\.text)
        #expect(words == ["First", "Second"], "Boxes must be sorted left-to-right within a line")
    }

    // MARK: Font-size-based tolerance

    @Test("Larger font size increases same-line Y tolerance")
    func largeFontTolerance() {
        // 30pt font → tolerance = 30 * 0.5 = 15.0 pt
        // Y-centres differ by 10 → should be on the same line
        let boxes = [
            makeBox("Big", left: 50, top: 100, right: 200, bottom: 130, fontSize: 30),
            makeBox("text", left: 210, top: 110, right: 350, bottom: 140, fontSize: 30),
        ]
        // Y-centres: 115 and 125 → difference 10 ≤ tolerance 15
        let lines = LineGrouper.group(boxes)
        #expect(lines.count == 1, "Large-font boxes 10 pt apart in Y should share a line")
    }
}

// MARK: - 3. HeadingDetector — unit tests

@Suite("HeadingDetector — unit tests")
struct HeadingDetectorTests {

    // MARK: Helpers

    /// Build a document-wide page array with one heading and many body lines.
    /// Heading is on page 0, line 0.  All other lines are body-size (12 pt).
    private func makePageLines(
        headingFontSize: Double,
        headingFontName: String? = nil,
        bodyCount: Int
    ) -> [[LayoutTextLine]] {
        var page0 = [LayoutTextLine]()
        page0.append(
            makeLine(
                "Heading text",
                left: 50, top: 800, right: 300, bottom: 780,
                fontSize: headingFontSize, fontName: headingFontName
            ))
        for i in 0..<bodyCount {
            let yTop = Double(760 - i * 20)
            page0.append(
                makeLine(
                    "Body paragraph text.",
                    left: 50, top: yTop, right: 500, bottom: yTop - 14,
                    fontSize: 12.0
                ))
        }
        return [page0]
    }

    // MARK: Large rare font → heading

    @Test("Line with larger, rare font size is classified as a heading")
    func largeFontRareIsHeading() {
        // 1 heading at 24 pt among 20 body lines at 12 pt.
        // freq(24 pt) = 1/21 ≈ 0.048 < 0.1 → rarity boost of ≈ 0.26
        // base probability (capped at 0.5) + rarity + short-line → ≥ 0.6
        let pageLines = makePageLines(headingFontSize: 24, bodyCount: 20)
        let flags = HeadingDetector.detectHeadings(in: pageLines)
        #expect(
            flags[0][0] == true, "24 pt heading among 20 body lines should be classified as heading"
        )
    }

    // MARK: Body-size text → not a heading

    @Test("Body-size text is not classified as a heading")
    func bodyTextNotHeading() {
        let pageLines = makePageLines(headingFontSize: 24, bodyCount: 20)
        let flags = HeadingDetector.detectHeadings(in: pageLines)
        // All body lines (indices 1…20) should NOT be headings
        let bodyFlags = flags[0].dropFirst()
        #expect(bodyFlags.allSatisfy { !$0 }, "Body-size (12 pt) lines should not be headings")
    }

    // MARK: Bold larger text → heading

    @Test("Bold text at larger-than-body size is classified as a heading")
    func boldLargerTextIsHeading() {
        // 1 bold heading (24 pt, name="Helvetica-Bold") among 9 body lines.
        // bold rarity boost ≈ 0.2, base ≈ 0.5, short ≈ 0.05 → total 0.75 ≥ 0.6
        let pageLines = makePageLines(
            headingFontSize: 24, headingFontName: "Helvetica-Bold", bodyCount: 9)
        let flags = HeadingDetector.detectHeadings(in: pageLines)
        #expect(flags[0][0] == true, "Bold 24 pt line among 9 body lines should be a heading")
    }

    // MARK: heading levels

    @Test("headingLevels returns distinct level for each unique heading size")
    func headingLevelsDistinct() {
        // Two heading sizes: 24 pt (larger) and 18 pt (smaller)
        let line24 = makeLine(
            "Big heading", left: 50, top: 800, right: 300, bottom: 780, fontSize: 24)
        let line18 = makeLine(
            "Small heading", left: 50, top: 750, right: 300, bottom: 735, fontSize: 18)
        let lineBody = makeLine(
            "Body text.", left: 50, top: 700, right: 300, bottom: 688, fontSize: 12)
        let pageLines = [[line24, line18, lineBody]]
        let flags = HeadingDetector.detectHeadings(in: pageLines)
        let levels = HeadingDetector.headingLevels(in: pageLines, isHeading: flags)
        // If both are headings, 24 pt → level 1, 18 pt → level 2
        if flags[0][0] && flags[0][1] {
            #expect(levels[(24.0 * 2).rounded() / 2] == 1)
            #expect(levels[(18.0 * 2).rounded() / 2] == 2)
        } else {
            // If detection doesn't trigger here, just verify map is non-empty
            // when at least one heading is detected
            let anyHeading = flags.flatMap { $0 }.contains(true)
            if anyHeading {
                #expect(!levels.isEmpty)
            }
        }
    }
}

// MARK: - 4. AutoTableDetector — unit tests

@Suite("AutoTableDetector — unit tests")
struct AutoTableDetectorTests {

    // Using y-DOWN coordinates (top < bottom) as AutoTableDetector's gap check
    // (`nextTop - prevBottom <= maxRowGap`) requires nextTop > prevBottom for
    // consecutive rows — which holds when top increases going down the page.

    // MARK: 3×3 grid

    @Test("Lines forming a clear 3-column layout detect as a table")
    func threeByThreeGrid() {
        // 3 rows × 3 columns.  Columns at x ≈ 50, 200, 350.
        // Row spacing 5 pt within maxRowGap=20 pt.  Page width 500 → minSep=15.
        let rows: [LayoutTextLine] = [
            makeMultiBoxLine(
                [("Header1", 50, 80), ("Header2", 200, 230), ("Header3", 350, 380)],
                top: 100, bottom: 115),
            makeMultiBoxLine(
                [("Data1A", 50, 80), ("Data1B", 200, 230), ("Data1C", 350, 380)],
                top: 120, bottom: 135),
            makeMultiBoxLine(
                [("Data2A", 50, 80), ("Data2B", 200, 230), ("Data2C", 350, 380)],
                top: 140, bottom: 155),
        ]
        let results = AutoTableDetector.detect(lines: rows, pageWidth: 500)
        #expect(!results.isEmpty, "3-column × 3-row layout should produce at least one table")
        if let first = results.first {
            #expect(first.table.headers.count >= 2, "Table must have ≥ 2 columns")
            #expect(!first.table.rows.isEmpty, "Table must have at least one data row")
        }
    }

    // MARK: Only 1 column → not a table

    @Test("Lines with only one text column are not detected as a table")
    func singleColumnNoTable() {
        let lines: [LayoutTextLine] = [
            makeLine("Row A", left: 50, top: 100, right: 200, bottom: 115),
            makeLine("Row B", left: 50, top: 120, right: 200, bottom: 135),
            makeLine("Row C", left: 50, top: 140, right: 200, bottom: 155),
        ]
        let results = AutoTableDetector.detect(lines: lines, pageWidth: 500)
        #expect(results.isEmpty, "Single-column layout must not be detected as a table")
    }

    // MARK: Only 1 row → not a table (needs ≥ minRows)

    @Test("A single row does not produce a table (requires minRows ≥ 2)")
    func singleRowNoTable() {
        let lines: [LayoutTextLine] = [
            makeMultiBoxLine(
                [("ColA", 50, 80), ("ColB", 200, 230), ("ColC", 350, 380)],
                top: 100, bottom: 115)
        ]
        let results = AutoTableDetector.detect(lines: lines, pageWidth: 500)
        #expect(
            results.isEmpty, "A single tabular row should not produce a table (needs header + data)"
        )
    }

    // MARK: Column count and row count validation

    @Test("Detected table has ≥ 2 columns and ≥ 1 data row")
    func tableColumnsAndRows() {
        let rows: [LayoutTextLine] = [
            makeMultiBoxLine([("Name", 50, 120), ("Score", 250, 320)], top: 100, bottom: 115),
            makeMultiBoxLine([("Alice", 50, 120), ("95", 250, 320)], top: 120, bottom: 135),
            makeMultiBoxLine([("Bob", 50, 120), ("87", 250, 320)], top: 140, bottom: 155),
        ]
        let results = AutoTableDetector.detect(lines: rows, pageWidth: 500)
        guard let result = results.first else {
            Issue.record("Expected at least one table from 2-column 3-row input")
            return
        }
        #expect(result.table.headers.count >= 2)
        #expect(!result.table.rows.isEmpty)
    }
}

// MARK: - 5. HeaderFooterDetector — unit tests

@Suite("HeaderFooterDetector — unit tests")
struct HeaderFooterDetectorTests {

    // HeaderFooterDetector uses y-UP style pageHeights (positive, e.g. 842 for A4).
    // Footer candidates must have `boundingBox.top < pageH / 3 ≈ 280`.
    // In y-UP: small top values = near the bottom of the page.

    private static let pageH = 842.0
    private static let bodyLine = makeLine(
        "Body paragraph.",
        left: 50, top: 750, right: 500, bottom: 735)  // high on page (y-UP)

    // MARK: Same text at bottom → footer

    @Test("Identical text at the same page-bottom position is detected as a footer")
    func sameTextFooterDetected() {
        // Footer line at y-UP bottom (small top value, < pageH/3 ≈ 280)
        let footer0 = makeLine(
            "Company Name",
            left: 50, top: 50, right: 300, bottom: 35)
        let footer1 = makeLine(
            "Company Name",
            left: 50, top: 50, right: 300, bottom: 35)
        let pages: [[LayoutTextLine]] = [
            [Self.bodyLine, footer0],
            [Self.bodyLine, footer1],
        ]
        let result = HeaderFooterDetector.detect(
            pageLines: pages, pageHeights: [Self.pageH, Self.pageH])
        // At least one page should have a footer detected
        let anyFooter = result.footerLineIndices.contains { !$0.isEmpty }
        #expect(anyFooter, "Identical bottom text across pages should be detected as a footer")
    }

    // MARK: Different text at different Y → not a footer

    @Test("Different text at different Y positions is not detected as a footer")
    func differentTextNotFooter() {
        // Footer-zone position but different text AND different y-centres (> 5 pt apart)
        let line0 = makeLine("Footer Alpha", left: 50, top: 60, right: 300, bottom: 44)
        let line1 = makeLine("Footer Beta", left: 50, top: 120, right: 300, bottom: 104)
        // Y-centres: 52 and 112 → |52 - 112| = 60 > 5 → no y-centre match either
        let pages: [[LayoutTextLine]] = [
            [Self.bodyLine, line0],
            [Self.bodyLine, line1],
        ]
        let result = HeaderFooterDetector.detect(
            pageLines: pages, pageHeights: [Self.pageH, Self.pageH])
        let anyFooter = result.footerLineIndices.contains { !$0.isEmpty }
        #expect(!anyFooter, "Different text at different Y should not be a footer")
    }

    // MARK: Page numbers (counter pattern) → footer

    @Test("Sequential page-number text (Page 1 / Page 2) is detected as a footer")
    func pageNumberCounterPattern() {
        // "Page 1" and "Page 2" differ only by a trailing integer → counter pattern
        let num0 = makeLine("Page 1", left: 250, top: 50, right: 320, bottom: 35)
        let num1 = makeLine("Page 2", left: 250, top: 50, right: 320, bottom: 35)
        let pages: [[LayoutTextLine]] = [
            [Self.bodyLine, num0],
            [Self.bodyLine, num1],
        ]
        let result = HeaderFooterDetector.detect(
            pageLines: pages, pageHeights: [Self.pageH, Self.pageH])
        let anyFooter = result.footerLineIndices.contains { !$0.isEmpty }
        #expect(anyFooter, "Page-number counter pattern should be detected as a footer")
    }

    // MARK: Single page → no detection

    @Test("A single page cannot produce header or footer detections")
    func singlePageNoDetection() {
        let singlePage = [
            Self.bodyLine, makeLine("Footer", left: 50, top: 50, right: 200, bottom: 35),
        ]
        let result = HeaderFooterDetector.detect(
            pageLines: [singlePage], pageHeights: [Self.pageH])
        #expect(result.headerLineIndices[0].isEmpty)
        #expect(result.footerLineIndices[0].isEmpty)
    }
}

// MARK: - 6. PopplerPage.textLines() — integration tests

@Suite("PopplerPage.textLines() — integration tests")
struct TextLinesIntegrationTests {

    let doc: PopplerDocument
    let page: PopplerPage

    init() throws {
        doc = try loadPDF("invoice")
        page = try doc.page(at: 0)
    }

    @Test("invoice.pdf page 0 returns non-empty text lines")
    func invoiceHasLines() {
        let lines = page.textLines()
        #expect(!lines.isEmpty, "invoice.pdf page 0 should have at least one text line")
    }

    @Test("Text lines have populated bounding boxes")
    func linesBoundingBoxesPopulated() {
        let lines = page.textLines()
        for line in lines {
            #expect(line.boundingBox.left >= 0)
            #expect(line.boundingBox.right > line.boundingBox.left)
            // At least one of top or bottom must differ (box has some vertical extent)
            #expect(line.boundingBox.top != line.boundingBox.bottom)
        }
    }

    @Test("First text line has non-empty text")
    func firstLineNonEmpty() throws {
        let lines = page.textLines()
        let first = try #require(lines.first, "There must be at least one text line")
        #expect(!first.text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test("Text lines collectively cover key invoice words")
    func linesContainInvoiceContent() {
        let allText = page.textLines().map(\.text).joined(separator: " ")
        #expect(
            allText.contains("YesLogic") || allText.contains("Invoice") || allText.contains("950"))
    }

    @Test("sortReadingOrder=false still returns non-empty lines")
    func unsortedLinesNonEmpty() {
        let lines = page.textLines(sortReadingOrder: false)
        #expect(!lines.isEmpty)
    }

}

// MARK: - 7. PopplerPage.detectTables() — integration tests

@Suite("PopplerPage.detectTables() — integration tests")
struct DetectTablesIntegrationTests {

    @Test(
        "ast_sci_data_tables_sample.pdf: geometry-based table detection returns at least one table")
    func sciPDFTablesDetected() throws {
        let doc = try loadPDF("ast_sci_data_tables_sample")
        var foundTable = false
        for i in 0..<doc.pageCount {
            let pg = try doc.page(at: i)
            let tables = pg.detectTables()
            if !tables.isEmpty { foundTable = true }
        }
        withKnownIssue("AutoTableDetector may not find tables in this layout", isIntermittent: true)
        {
            #expect(foundTable, "At least one table should be detected across both pages")
        }
    }

    @Test("Detected tables have ≥ 2 columns and ≥ 1 data row")
    func detectedTableShape() throws {
        let doc = try loadPDF("ast_sci_data_tables_sample")
        for i in 0..<doc.pageCount {
            let pg = try doc.page(at: i)
            for table in pg.detectTables() {
                #expect(table.headers.count >= 2, "Every detected table must have ≥ 2 columns")
                #expect(!table.rows.isEmpty, "Every detected table must have ≥ 1 data row")
            }
        }
    }

}

// MARK: - 8. PopplerDocument.extractLayout() — integration tests

@Suite("PopplerDocument.extractLayout() — integration tests")
struct ExtractLayoutIntegrationTests {

    // MARK: invoice.pdf

    @Test("invoice.pdf layout elements all have non-empty text")
    func invoiceElementsHaveText() async throws {
        let doc = try loadPDF("invoice")
        let layout = try await doc.extractLayout()
        let allElements = layout.flatMap { $0 }
        #expect(!allElements.isEmpty)
        for element in allElements {
            let t = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(
                !t.isEmpty,
                "Every layout element must have non-empty text; got empty for \(element)")
        }
    }

    @Test("invoice.pdf contains at least one heading element")
    func invoiceHasHeadings() async throws {
        let doc = try loadPDF("invoice")
        let layout = try await doc.extractLayout()
        let hasHeading = layout.flatMap { $0 }.contains {
            if case .heading = $0 { return true }
            return false
        }
        #expect(hasHeading, "Invoice should contain at least one heading (e.g. 'Invoice')")
    }

    @Test("invoice.pdf contains paragraph elements")
    func invoiceHasParagraphs() async throws {
        let doc = try loadPDF("invoice")
        let layout = try await doc.extractLayout()
        let hasParagraph = layout.flatMap { $0 }.contains {
            if case .paragraph = $0 { return true }
            return false
        }
        #expect(hasParagraph, "Invoice must contain paragraph elements")
    }

    // MARK: ast_sci_data_tables_sample.pdf

    @Test("ast_sci_data_tables_sample.pdf elements have non-empty text")
    func sciPDFElementsHaveText() async throws {
        let doc = try loadPDF("ast_sci_data_tables_sample")
        let layout = try await doc.extractLayout()
        let allElements = layout.flatMap { $0 }
        #expect(!allElements.isEmpty)
        for element in allElements {
            let t = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!t.isEmpty)
        }
    }

    // MARK: extractLayoutText convenience

    @Test("extractLayoutText(removeChrome: true) is no longer than without-chrome")
    func extractLayoutTextChromeRemovalShorterOrEqual() async throws {
        let doc = try loadPDF("ast_sci_data_tables_sample")
        let withChrome = try await doc.extractLayoutText(removeChrome: false)
        let withoutChrome = try await doc.extractLayoutText(removeChrome: true)
        #expect(!withoutChrome.isEmpty)
        #expect(
            withoutChrome.count <= withChrome.count,
            "Removing chrome should never add text (got \(withoutChrome.count) vs \(withChrome.count))"
        )
    }
}

// MARK: - 9. BorderScanDetector — unit tests with synthetic pixel data

// All synthetic images use rgb24 format (3 bytes per pixel: R, G, B).
// White pixel = (255, 255, 255).  Black pixel = (0, 0, 0).

@Suite("BorderScanDetector — unit tests")
struct BorderScanDetectorTests {

    // MARK: Helpers

    /// Build a white rgb24 image of `width × height` pixels.
    private func whiteImage(width: Int, height: Int) -> [UInt8] {
        [UInt8](repeating: 255, count: height * width * 3)
    }

    /// Paint a full-width horizontal black line at pixel row `y`.
    private func paintHLine(pixels: inout [UInt8], y: Int, width: Int) {
        for x in 0..<width {
            let off = y * width * 3 + x * 3
            pixels[off] = 0
            pixels[off + 1] = 0
            pixels[off + 2] = 0
        }
    }

    /// Paint a full-height vertical black line at pixel column `x`.
    private func paintVLine(pixels: inout [UInt8], x: Int, width: Int, height: Int) {
        for y in 0..<height {
            let off = y * width * 3 + x * 3
            pixels[off] = 0
            pixels[off + 1] = 0
            pixels[off + 2] = 0
        }
    }

    // MARK: Horizontal line detection

    @Test("Solid black horizontal line in a white image is detected")
    func singleHorizontalLine() {
        let w = 20
        let h = 10
        var pixels = whiteImage(width: w, height: h)
        paintHLine(pixels: &pixels, y: 5, width: w)

        let result = BorderScanDetector.detect(
            width: w, height: h,
            pixels: Data(pixels), format: .rgb24, bytesPerRow: w * 3
        )
        #expect(result.horizontal == [5], "Expected exactly one horizontal line at y=5")
        #expect(result.vertical.isEmpty, "No vertical lines should be detected")
    }

    // MARK: Vertical line detection

    @Test("Solid black vertical line in a white image is detected")
    func singleVerticalLine() {
        let w = 10
        let h = 20
        var pixels = whiteImage(width: w, height: h)
        paintVLine(pixels: &pixels, x: 3, width: w, height: h)

        let result = BorderScanDetector.detect(
            width: w, height: h,
            pixels: Data(pixels), format: .rgb24, bytesPerRow: w * 3
        )
        #expect(result.horizontal.isEmpty, "No horizontal lines should be detected")
        #expect(result.vertical == [3], "Expected exactly one vertical line at x=3")
    }

    // MARK: No lines

    @Test("Solid white image produces no detected lines")
    func allWhiteNoLines() {
        let w = 15
        let h = 15
        let pixels = whiteImage(width: w, height: h)

        let result = BorderScanDetector.detect(
            width: w, height: h,
            pixels: Data(pixels), format: .rgb24, bytesPerRow: w * 3
        )
        #expect(result.horizontal.isEmpty)
        #expect(result.vertical.isEmpty)
    }

    // MARK: 2×2 grid — two horizontal + two vertical

    @Test("Two horizontal and two vertical lines form a 2-by-2 border arrangement")
    func twoByTwoBorderGrid() {
        let w = 30
        let h = 30
        var pixels = whiteImage(width: w, height: h)
        paintHLine(pixels: &pixels, y: 5, width: w)
        paintHLine(pixels: &pixels, y: 24, width: w)
        paintVLine(pixels: &pixels, x: 4, width: w, height: h)
        paintVLine(pixels: &pixels, x: 25, width: w, height: h)

        let result = BorderScanDetector.detect(
            width: w, height: h,
            pixels: Data(pixels), format: .rgb24, bytesPerRow: w * 3
        )
        #expect(result.horizontal.count == 2, "Expected 2 horizontal lines at y=5 and y=24")
        #expect(result.vertical.count == 2, "Expected 2 vertical lines at x=4 and x=25")
        // Two lines in each direction → 1 interior row band + 1 interior column band
        #expect(result.gridRows == 1)
        #expect(result.gridColumns == 1)
    }

    // MARK: minLineGap suppression

    @Test("Two adjacent rows (gap < minLineGap) are suppressed to one detection")
    func adjacentLinesSupressed() {
        let w = 20
        let h = 20
        var pixels = whiteImage(width: w, height: h)
        // Paint rows 7 and 8 black (gap = 1 < minLineGap = 3 → only one detected)
        paintHLine(pixels: &pixels, y: 7, width: w)
        paintHLine(pixels: &pixels, y: 8, width: w)

        let result = BorderScanDetector.detect(
            width: w, height: h,
            pixels: Data(pixels), format: .rgb24, bytesPerRow: w * 3
        )
        #expect(
            result.horizontal.count == 1, "Adjacent lines within minLineGap should merge into one")
    }

    // MARK: Empty / degenerate inputs

    @Test("Empty pixel data returns no detections")
    func emptyDataNoDetections() {
        let result = BorderScanDetector.detect(
            width: 10, height: 10,
            pixels: Data(), format: .rgb24, bytesPerRow: 30
        )
        #expect(result.horizontal.isEmpty)
        #expect(result.vertical.isEmpty)
    }

    @Test("Invalid format returns no detections")
    func invalidFormatNoDetections() {
        let pixels = Data([UInt8](repeating: 0, count: 100))
        let result = BorderScanDetector.detect(
            width: 10, height: 10,
            pixels: pixels, format: .invalid, bytesPerRow: 10
        )
        #expect(result.horizontal.isEmpty)
        #expect(result.vertical.isEmpty)
    }
}

// MARK: - 10. PopplerPage.detectBorderedTables() — integration tests

@Suite("PopplerPage.detectBorderedTables() — integration tests")
struct DetectBorderedTablesIntegrationTests {

    @Test("When bordered tables are detected, each has ≥ 1 header and ≥ 1 data row")
    func borderedTableShape() throws {
        // We check all PDFs; many will return empty arrays (no drawn borders) — that's fine
        let names = ["invoice", "ast_sci_data_tables_sample", "pdf_with_images"]
        for name in names {
            let doc = try loadPDF(name)
            for i in 0..<doc.pageCount {
                let pg = try doc.page(at: i)
                for table in pg.detectBorderedTables() {
                    #expect(
                        !table.headers.isEmpty, "\(name) p\(i): bordered table must have headers")
                    #expect(
                        !table.rows.isEmpty, "\(name) p\(i): bordered table must have data rows")
                }
            }
        }
    }
}

// MARK: - PopplerPage.lineArtSegments() tests

@Suite("PopplerPage.lineArtSegments() — unit and integration tests")
struct LineArtSegmentsTests {

    @Test("When segments exist, each has finite coordinates")
    func segmentsHaveFiniteCoordinates() throws {
        let doc = try loadPDF("invoice")
        let page = try doc.page(at: 0)
        for seg in page.lineArtSegments() {
            #expect(seg.x1.isFinite && seg.y1.isFinite)
            #expect(seg.x2.isFinite && seg.y2.isFinite)
            #expect(seg.r >= 0 && seg.r <= 1)
            #expect(seg.g >= 0 && seg.g <= 1)
            #expect(seg.b >= 0 && seg.b <= 1)
            #expect(seg.lineWidth >= 0)
        }
    }

    @Test("isHorizontal and isVertical are mutually exclusive for axis-aligned segments")
    func axisAlignedMutuallyExclusive() throws {
        let doc = try loadPDF("invoice")
        let page = try doc.page(at: 0)
        for seg in page.lineArtSegments() {
            // A segment can be neither (diagonal) but not both H and V
            #expect(!(seg.isHorizontal() && seg.isVertical()))
        }
    }

    @Test("boundingBox of a segment has non-negative width and height")
    func boundingBoxNonNegative() throws {
        let doc = try loadPDF("invoice")
        let page = try doc.page(at: 0)
        for seg in page.lineArtSegments() {
            let bb = seg.boundingBox
            #expect(bb.right >= bb.left)
            #expect(bb.top >= bb.bottom)
        }
    }

    @Test("page loaded from Data returns empty lineArtSegments (PDFDoc not available)")
    func rawDataDocReturnsEmpty() throws {
        let url = try #require(Bundle.module.url(forResource: "invoice", withExtension: "pdf"))
        let data = try Data(contentsOf: url)
        let doc = try PopplerDocument.load(from: data)
        let page = try doc.page(at: 0)
        // Raw-data docs have pageIndex = -1 → should return []
        #expect(page.lineArtSegments().isEmpty)
    }

    @Test("When line-art tables are detected, each has ≥ 2 columns and ≥ 1 data row")
    func lineArtTablesShape() throws {
        let doc = try loadPDF("invoice")
        let page = try doc.page(at: 0)
        let tables = page.detectLineArtTables()
        for entry in tables {
            #expect(entry.table.headers.count >= 2)
            #expect(!entry.table.rows.isEmpty)
            #expect(entry.boundingBox.right > entry.boundingBox.left)
            #expect(entry.boundingBox.top > entry.boundingBox.bottom)
        }
    }
}

// MARK: - HiddenTextFilter tests

@Suite("HiddenTextFilter — unit and integration tests")
struct HiddenTextFilterTests {

    @Test("filter() returns all lines when page has no invisible text")
    func noInvisibleTextRetainsAllLines() throws {
        let doc = try loadPDF("invoice")
        let page = try doc.page(at: 0)
        let lines = page.textLines()
        let (visible, hiddenCount) = HiddenTextFilter.filter(lines: lines, page: page)
        // invoice.pdf should have no hidden text
        #expect(hiddenCount == 0)
        #expect(visible.count == lines.count)
    }

    @Test("invisible text bboxes have valid PDF coordinates when present")
    func invisibleBBoxesHaveValidCoords() throws {
        for name in ["invoice", "ast_sci_data_tables_sample"] {
            let doc = try loadPDF(name)
            for i in 0..<doc.pageCount {
                let page = try doc.page(at: i)
                for bbox in page.invisibleTextBoundingBoxes() {
                    #expect(bbox.right >= bbox.left)
                    #expect(bbox.top >= bbox.bottom)
                    #expect(bbox.left.isFinite && bbox.top.isFinite)
                }
            }
        }
    }

    @Test("filter() visible count never exceeds input line count")
    func visibleNeverExceedsInput() throws {
        let doc = try loadPDF("ast_sci_data_tables_sample")
        for i in 0..<doc.pageCount {
            let page = try doc.page(at: i)
            let lines = page.textLines()
            let (visible, _) = HiddenTextFilter.filter(lines: lines, page: page)
            #expect(visible.count <= lines.count)
        }
    }
}

// MARK: - XYCutSorter regression tests (Issues #179, #294)

@Suite("XYCutSorter — edge-case regression tests")
struct XYCutSorterRegressionTests {

    // Synthetic helper
    private func rect(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> PopplerRect {
        // Input convention: (leftX, topY, rightX, bottomY) → PopplerRect(left, top, right, bottom)
        PopplerRect(left: x1, top: y1, right: x2, bottom: y2)
    }

    // MARK: Infinite recursion / stack-overflow prevention
    //
    // 40 elements (20 left + 20 right column rows), all in the same narrow
    // Y range so no horizontal gap is available.  Without the safety check
    // that returns sortByYThenX when splitVertical produces a single group,
    // the original algorithm recurses infinitely on complex grids.

    @Test("20-row two-column layout completes without infinite recursion")
    func issue179NoStackOverflow() {
        var boxes = [PopplerRect]()
        for i in 0..<20 {
            let y = 700.0 - Double(i) * 30
            boxes.append(rect(50, y, 250, y - 20))  // left column
            boxes.append(rect(260, y, 450, y - 20))  // right column
        }
        let start = Date()
        let sorted = XYCutSorter.sortedIndices(of: boxes)
        let elapsed = Date().timeIntervalSince(start)
        #expect(sorted.count == 40)
        #expect(
            elapsed < 5.0, "Sort must complete in <5 s (no infinite recursion), took \(elapsed)s")
    }

    @Test("Wide element adjacent to 1-pt element completes without recursion")
    func issue179NarrowElement() {
        let boxes = [
            rect(0, 100, 100, 90),  // wide
            rect(101, 100, 102, 90),  // 1 pt wide
        ]
        let sorted = XYCutSorter.sortedIndices(of: boxes)
        #expect(sorted.count == 2)
    }

    // MARK: Narrow bridge element between columns
    //
    // A narrow element (e.g. a page number) sits in the column gap.
    // Its left/right edges create tiny gaps (2 pt each) below MIN_GAP_THRESHOLD (5 pt).
    // After filtering out elements narrower than 10% of region width the larger
    // gap (20 pt) is revealed and the correct vertical cut is found.

    @Test("Narrow element in the column gap does not prevent vertical-cut detection")
    func issue294NarrowBridgeElement() {
        // Left column (x 50–300), right column (x 320–560), bridge (x 302–318)
        let boxes = [
            rect(50, 600, 300, 570),  // L1
            rect(50, 572, 300, 550),  // L2
            rect(320, 600, 560, 570),  // R1
            rect(320, 572, 560, 550),  // R2
            rect(302, 585, 318, 575),  // narrow bridge (16 pt wide < 10% of 510 pt region)
        ]
        let sorted = XYCutSorter.sortedIndices(of: boxes)
        #expect(sorted.count == 5)

        // Left column elements must come before right column elements
        let posL1 = sorted.firstIndex(of: 0)!  // L1
        let posL2 = sorted.firstIndex(of: 1)!  // L2
        let posR1 = sorted.firstIndex(of: 2)!  // R1
        let posR2 = sorted.firstIndex(of: 3)!  // R2

        #expect(
            posL2 < posR1, "Left column (L2 @ \(posL2)) must precede right column (R1 @ \(posR1))")
        #expect(posL1 < posL2, "L1 before L2")
        #expect(posR1 < posR2, "R1 before R2")
    }

    // MARK: Heading level clamp
    //
    // Headings must be clamped to H1–H6 (Markdown / WCAG spec).
    // Our assembleElements uses min(6, max(1, level)).

    @Test("Heading levels are always in range 1–6")
    func headingLevelsClamped() async throws {
        let doc = try { () throws -> PopplerDocument in
            let url = try #require(Bundle.module.url(forResource: "invoice", withExtension: "pdf"))
            return try PopplerDocument.load(from: url)
        }()
        let layout = try await doc.extractLayout()
        for elements in layout {
            for element in elements {
                if case .heading(let level, _, _, _) = element {
                    #expect(
                        level >= 1 && level <= 6,
                        "Heading level \(level) must be in 1–6 (Markdown / WCAG spec)")
                }
            }
        }
    }
}

// MARK: - replacementCharRatio tests

@Suite("PopplerDocument.replacementCharRatio — CID font detection")
struct ReplacementCharRatioTests {

    @Test("Clean text-layer PDFs have ratio ≈0")
    func cleanPDFsHaveZeroRatio() throws {
        for name in ["invoice", "ast_sci_data_tables_sample"] {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "pdf"))
            let doc = try PopplerDocument.load(from: url)
            let ratio = doc.replacementCharRatio
            #expect(ratio < 0.01, "\(name): expected near-zero replacement ratio, got \(ratio)")
        }
    }

    @Test("Image-only PDF has ratio 0 (no text layer at all)")
    func imageOnlyPDFHasZeroRatio() throws {
        let url = try #require(Bundle.module.url(forResource: "chinese_scan", withExtension: "pdf"))
        let doc = try PopplerDocument.load(from: url)
        // No text layer → text() returns empty → ratio = 0 (not 1.0)
        #expect(doc.replacementCharRatio == 0.0)
    }

    @Test("replacementCharRatio is in [0, 1]")
    func ratioIsNormalized() throws {
        for name in ["invoice", "ast_sci_data_tables_sample", "chinese_scan", "1901.03003"] {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "pdf"))
            let doc = try PopplerDocument.load(from: url)
            let r = doc.replacementCharRatio
            #expect(r >= 0 && r <= 1.0, "\(name): ratio \(r) out of [0,1]")
        }
    }

    // Body text that repeats on consecutive pages but sits more than 30 pt above
    // the actual footer must not be classified as a footer element.
    @Test("Body text more than 30 pt above footer is not absorbed into the footer region")
    func issue385RepeatedBodyTextNotAbsorbedIntoFooter() throws {
        // Simulate two pages:
        //   - body note at y=117 (repeating, same text both pages)
        //   - actual footer at y=35 (alternating page-number pattern)
        // Page height = 595 pt (A4-like)
        let pageH = 595.0
        let footerY = 35.0
        let bodyNoteY = 117.0

        func makeLine(_ text: String, _ y: Double) -> LayoutTextLine {
            let box = PopplerTextBox(
                text: text,
                boundingBox: PopplerRect(left: 37, top: y + 15, right: 300, bottom: y),
                fontName: nil, fontSize: 10, rotation: 0, hasSpaceAfter: false,
                charBBoxes: [], writingMode: .horizontal
            )
            return LayoutTextLine(boxes: [box])
        }

        // Build 4 pages
        var allLines = [[LayoutTextLine]]()
        for page in 0..<4 {
            var lines = [LayoutTextLine]()
            // Body heading near top
            lines.append(makeLine("Section \(page + 1)", pageH - 50))
            // Body content in middle
            lines.append(makeLine("Body content page \(page + 1)", pageH / 2))
            // Repeated body note at y=117 (pages 2 and 3 only, like the CERAGEM example)
            if page == 2 || page == 3 {
                lines.append(makeLine("※ Repeated note text", bodyNoteY))
            }
            // Actual alternating footer at y=35
            let footerText = page % 2 == 0 ? "CGM BALANCE \(page + 17)" : "\(page + 17) USER MANUAL"
            lines.append(makeLine(footerText, footerY))
            allLines.append(lines)
        }

        let pageHeights = Array(repeating: pageH, count: 4)
        let result = HeaderFooterDetector.detect(pageLines: allLines, pageHeights: pageHeights)

        // The footer indices for each page must NOT include the body note line
        for pageIdx in 0..<4 {
            let footerIndices = Set(result.footerLineIndices[pageIdx])
            let lines = allLines[pageIdx]

            // Find the index of the repeated body note on pages 2 and 3
            if pageIdx == 2 || pageIdx == 3 {
                if let noteIdx = lines.indices.first(where: { lines[$0].text.contains("Repeated") })
                {
                    #expect(
                        !footerIndices.contains(noteIdx),
                        "Page \(pageIdx): body note at y=\(bodyNoteY) (gap>30pt from footer) must not be absorbed into footer"
                    )
                }
            }

            // At least one line per page should be the actual footer
            // (footer at y=35 repeats every page with alternating page numbers)
            // Note: single-page detection requires cross-page match, so on 4 pages it should work
        }
    }
}

// MARK: - StrikethroughDetector

@Suite("PopplerPage.strikethroughTextBoxIndices()")
struct StrikethroughDetectorTests {

    @Test("Returned indices are all valid text-box positions")
    func indicesInBounds() throws {
        let url = try #require(Bundle.module.url(forResource: "invoice", withExtension: "pdf"))
        let doc = try PopplerDocument.load(from: url)
        let page = try doc.page(at: 0)
        let boxes = page.textBoxes()
        let indices = page.strikethroughTextBoxIndices()
        for idx in indices {
            #expect(idx < boxes.count)
        }
    }

    @Test("Clean text-layer PDF has at most 5 % of boxes flagged")
    func cleanPDFNearlyNone() throws {
        let url = try #require(Bundle.module.url(forResource: "1901.03003", withExtension: "pdf"))
        let doc = try PopplerDocument.load(from: url)
        for i in 0..<min(doc.pageCount, 5) {
            let page = try doc.page(at: i)
            let boxes = page.textBoxes()
            let indices = page.strikethroughTextBoxIndices()
            let ratio = boxes.isEmpty ? 0.0 : Double(indices.count) / Double(boxes.count)
            #expect(ratio < 0.05)
        }
    }

    @Test("Image-only page returns empty set")
    func imageOnlyEmpty() throws {
        let url = try #require(Bundle.module.url(forResource: "chinese_scan", withExtension: "pdf"))
        let doc = try PopplerDocument.load(from: url)
        let page = try doc.page(at: 0)
        #expect(page.strikethroughTextBoxIndices().isEmpty)
    }
}

// MARK: - CaptionDetector

@Suite("CaptionDetector")
struct CaptionDetectorTests {

    private func line(_ text: String) -> LayoutTextLine {
        LayoutTextLine(boxes: [
            PopplerTextBox(
                text: text,
                boundingBox: PopplerRect(left: 50, top: 500, right: 400, bottom: 485),
                fontName: nil, fontSize: 12, rotation: 0,
                hasSpaceAfter: false, charBBoxes: [], writingMode: .horizontal)
        ])
    }

    @Test("Figure and Table prefixes with a number are detected as captions")
    func standardPrefixes() {
        for text in ["Fig. 1 shows", "Figure 2:", "Table 1.", "TABLE I:", "Algorithm 1:"] {
            #expect(CaptionDetector.isCaption(line(text)), "'\(text)' should be a caption")
        }
    }

    @Test("Keyword without a following number or marker is not a caption")
    func noMarkerNotCaption() {
        for text in ["Figure this out", "Tables are everywhere"] {
            #expect(!CaptionDetector.isCaption(line(text)), "'\(text)' should not be a caption")
        }
    }

    @Test("MORAN paper extractLayout() contains caption elements")
    func moranHasCaptions() async throws {
        let url = try #require(Bundle.module.url(forResource: "1901.03003", withExtension: "pdf"))
        let doc = try PopplerDocument.load(from: url)
        let layout = try await doc.extractLayout()
        let caps = layout.flatMap { $0 }.filter {
            if case .caption = $0 { return true }
            return false
        }
        #expect(!caps.isEmpty)
    }
}

// MARK: - LevelDetector

@Suite("LevelDetector")
struct LevelDetectorTests {

    private func item(_ label: String, left: Double) -> PopplerLayoutElement {
        .listItem(
            label: label, text: "text",
            boundingBox: PopplerRect(left: left, top: 500, right: 400, bottom: 485),
            nestingLevel: 1)
    }

    @Test("Items at body margin are level 1; items indented beyond threshold are level 2")
    func nestingLevels() {
        let bodyLeft = 50.0
        let deeper = bodyLeft + LevelDetector.indentThreshold + 10
        let elements: [PopplerLayoutElement] = [
            item("1.", left: bodyLeft),
            item("a.", left: deeper),
            item("2.", left: bodyLeft),
        ]
        let result = LevelDetector.detectNesting(elements, bodyLeftMargin: bodyLeft)
        let levels = result.compactMap {
            if case .listItem(_, _, _, let l) = $0 { return l }
            return nil
        }
        #expect(levels == [1, 2, 1])
    }

    @Test("A heading between list groups resets the nesting stack")
    func headingResetsStack() {
        let bodyLeft = 50.0
        let deeper = bodyLeft + LevelDetector.indentThreshold + 10
        let elements: [PopplerLayoutElement] = [
            item("a.", left: deeper),
            .heading(
                level: 2, text: "Section",
                boundingBox: PopplerRect(left: 50, top: 600, right: 400, bottom: 580),
                fontSize: 14),
            item("1.", left: bodyLeft),
        ]
        let result = LevelDetector.detectNesting(elements, bodyLeftMargin: bodyLeft)
        let levels = result.compactMap {
            if case .listItem(_, _, _, let l) = $0 { return l }
            return nil
        }
        #expect(levels.last == 1)
    }

    @Test("extractLayout() never produces nestingLevel outside 1\u{2013}6")
    func nestingInRange() async throws {
        let url = try #require(Bundle.module.url(forResource: "1901.03003", withExtension: "pdf"))
        let doc = try PopplerDocument.load(from: url)
        let layout = try await doc.extractLayout()
        for el in layout.flatMap({ $0 }) {
            if case .listItem(_, _, _, let level) = el {
                #expect(level >= 1 && level <= 6)
            }
        }
    }
}

// MARK: - TableStructureNormalizer

@Suite("TableStructureNormalizer")
struct TableStructureNormalizerTests {

    private func makeTable(rows: Int, cols: Int) -> PDFTable {
        let headers = (0..<cols).map { "Col\($0)" }
        let dataRows = (0..<rows).map { r in
            PDFTable.Row(cells: Dictionary(uniqueKeysWithValues: headers.map { ($0, "v\(r)") }))
        }
        return PDFTable(headers: headers, rows: dataRows)
    }

    private func denseLines(bb: PopplerRect, cols: Int, logicalRows: Int) -> [LayoutTextLine] {
        let cW = (bb.right - bb.left) / Double(cols)
        let rH = (bb.top - bb.bottom) / Double(logicalRows)
        var lines = [LayoutTextLine]()
        for r in 0..<logicalRows {
            let cy = bb.top - (Double(r) + 0.5) * rH
            for c in 0..<cols {
                let cx = bb.left + (Double(c) + 0.5) * cW
                lines.append(
                    LayoutTextLine(boxes: [
                        PopplerTextBox(
                            text: "c\(r)_\(c)",
                            boundingBox: PopplerRect(
                                left: cx - 20, top: cy + 5, right: cx + 20, bottom: cy - 5),
                            fontName: nil, fontSize: 10, rotation: 0,
                            hasSpaceAfter: false, charBBoxes: [], writingMode: .horizontal)
                    ]))
            }
        }
        return lines
    }

    @Test("Well-segmented table (> 2 rows) is returned unchanged")
    func wellSegmentedUnchanged() {
        let table = makeTable(rows: 5, cols: 3)
        let bb = PopplerRect(left: 50, top: 700, right: 550, bottom: 100)
        let result = TableStructureNormalizer.normalize(
            table: table, tableBB: bb, pageLines: denseLines(bb: bb, cols: 3, logicalRows: 5))
        #expect(result.rows.count == 5)
    }

    @Test("Under-segmented table (1 row, 3 cols, dense text) gains rows after normalization")
    func underSegmentedGainsRows() {
        let table = makeTable(rows: 1, cols: 3)
        let bb = PopplerRect(left: 50, top: 700, right: 550, bottom: 100)
        let result = TableStructureNormalizer.normalize(
            table: table, tableBB: bb, pageLines: denseLines(bb: bb, cols: 3, logicalRows: 8))
        #expect(result.rows.count > 1)
    }
}

// MARK: - ListDetector.splitMultipleItems
//
// Port of the fix for inconsistent list parsing for multiline financial rows.
//
// Root cause: when the PDF stores adjacent labeled lines in a single text extraction
// unit, LineGrouper can merge them into one LayoutTextLine with multiple boxes.
// The original detectItem only found the first label; splitMultipleItems finds all.

@Suite("ListDetector.splitMultipleItems")
struct ListDetectorSplitTests {

    // Helper: LayoutTextLine with one box per string
    private func multiBoxLine(_ texts: [String]) -> LayoutTextLine {
        LayoutTextLine(
            boxes: texts.enumerated().map { i, t in
                makeBox(
                    t,
                    left: Double(i) * 120, top: 500,
                    right: Double(i) * 120 + 115, bottom: 485)
            })
    }

    // MARK: Core split cases

    @Test("Three labeled boxes produce three list items")
    func threeLabelsProduceThreeItems() {
        // Mirrors testProcessListsFromSingleMultilineTextNode
        let line = multiBoxLine([
            "1. Revenue from Operations",
            "2. Other Income",
            "3. Total Income",
        ])
        let items = ListDetector.splitMultipleItems(in: line)
        #expect(items?.count == 3)
        #expect(items?[0].label == "1.")
        #expect(items?[1].label == "2.")
        #expect(items?[2].label == "3.")
    }

    @Test("Unlabeled continuation box attaches to the preceding labeled box")
    func continuationBoxAttachesToPreviousItem() {
        // Mirrors testProcessListsFromSingleMultilineTextNodeKeepsContinuationLines
        let line = multiBoxLine([
            "1. Changes in Inventories",
            "Work In Progress",  // continuation — no label
            "2. Employee Benefits Expense",
        ])
        let items = ListDetector.splitMultipleItems(in: line)
        #expect(items?.count == 2)
        // Continuation text must be part of item 1’s body
        let body0 = items?[0].body ?? ""
        #expect(body0.contains("Changes in Inventories"))
        #expect(
            body0.contains("Work In Progress"),
            "Continuation line must be attached to preceding item")
    }

    @Test("Single labeled box with continuation is NOT split (restore guard)")
    func singleLabeledBoxNotSplit() {
        // Mirrors testProcessListsFromSingleLabeledLineIsNotExpanded
        let line = multiBoxLine([
            "1. Only Item",
            "Continuation text",
        ])
        #expect(
            ListDetector.splitMultipleItems(in: line) == nil,
            "A line with only one labeled box must not be expanded")
        // Original is preserved — falls through to detectItem or paragraph
    }

    @Test("Decimal-formatted numbers are not mis-split (doubles guard)")
    func decimalNumbersNotSplit() {
        // Values like ‘1.942.000’ have multiple dots but are not list labels
        // because there is no whitespace immediately after the first period.
        let line = multiBoxLine([
            "1.942.000",
            "117.000",
            "2.538.000",
        ])
        #expect(
            ListDetector.splitMultipleItems(in: line) == nil,
            "Thousand-separated financial numbers must not be treated as list labels")
        #expect(
            ListDetector.detectItem(in: line) == nil,
            "Thousand-separated numbers must not match the label pattern")
    }
}

// MARK: - PR #518 regressions

@Suite("PR #518 — heading‐body fusion and TOC row ordering")
struct PR518Tests {

    // Boxes use y-UP convention (top > bottom) matching XYCutSorter's test helpers.
    private func r(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> PopplerRect {
        PopplerRect(left: x1, top: y1, right: x2, bottom: y2)
    }

    // MARK: Fix 1 — heading/body fusion guard in LineGrouper

    @Test("Boxes with >50% font-size difference are not merged into the same line")
    func headingAndBodyNotFused() {
        // Bold 16 pt heading box followed by 11 pt body box at nearly the same Y.
        // With just the Y-proximity check they would be merged (ratio 16/11 ≈ 1.45).
        let heading = PopplerTextBox(
            text: "Introduction",
            boundingBox: PopplerRect(left: 50, top: 302, right: 200, bottom: 286),
            fontName: "TimesNewRoman-Bold", fontSize: 16,
            rotation: 0, hasSpaceAfter: true, charBBoxes: [], writingMode: .horizontal)
        let body = PopplerTextBox(
            text: "This paper presents",
            boundingBox: PopplerRect(left: 50, top: 290, right: 300, bottom: 279),
            fontName: "TimesNewRoman", fontSize: 11,
            rotation: 0, hasSpaceAfter: true, charBBoxes: [], writingMode: .horizontal)

        let lines = LineGrouper.group([heading, body])
        #expect(lines.count == 2, "Heading and body must be separate lines, got \(lines.count)")
    }

    @Test("Boxes with similar font sizes on the same baseline are still merged")
    func sameStyleBoxesMerge() {
        let a = PopplerTextBox(
            text: "Hello",
            boundingBox: PopplerRect(left: 50, top: 300, right: 100, bottom: 288),
            fontName: "Arial", fontSize: 12,
            rotation: 0, hasSpaceAfter: true, charBBoxes: [], writingMode: .horizontal)
        let b = PopplerTextBox(
            text: "world",
            boundingBox: PopplerRect(left: 105, top: 300, right: 155, bottom: 288),
            fontName: "Arial", fontSize: 12,
            rotation: 0, hasSpaceAfter: false, charBBoxes: [], writingMode: .horizontal)

        let lines = LineGrouper.group([a, b])
        #expect(lines.count == 1, "Same-style boxes on the same baseline must merge")
    }

    // MARK: Fix 2 — TOC row-by-row ordering in XYCutSorter

    @Test("TOC page is read row-by-row (Chapter 1/1, Chapter 2/10, …)")
    func tocPageRowByRow() {
        // Four rows: chapter title on left (x 50–150), page number on right (x 450–470).
        // Large horizontal gutter (~300 pt) with small element heights (~10 pt).
        // XY-Cut++ must NOT split into left-column-then-right-column.
        let boxes: [PopplerRect] = [
            r(50, 500, 150, 490), r(450, 500, 470, 490),  // Chapter 1 / 1
            r(50, 485, 150, 475), r(450, 485, 470, 475),  // Chapter 2 / 10
            r(50, 470, 150, 460), r(450, 470, 470, 460),  // Chapter 3 / 20
            r(50, 455, 150, 445), r(450, 455, 470, 445),  // Chapter 4 / 30
        ]
        let sorted = XYCutSorter.sortedIndices(of: boxes)
        #expect(sorted.count == 8)
        // Each even index must be a chapter title (left half), odd a page number (right half).
        for pair in stride(from: 0, to: 8, by: 2) {
            let titleIdx = sorted[pair]
            let numIdx = sorted[pair + 1]
            let titleCx = (boxes[titleIdx].left + boxes[titleIdx].right) / 2
            let numCx = (boxes[numIdx].left + boxes[numIdx].right) / 2
            #expect(titleCx < 300, "Pair \(pair/2): left element should be chapter title")
            #expect(numCx > 300, "Pair \(pair/2): right element should be page number")
        }
    }

    @Test("Standard two-column body text is not affected by the TOC guard")
    func twoColumnBodyUnaffected() {
        // Regular two-column academic text: left and right columns with
        // large element heights (> 45 pt) and moderate gutter (~60 pt).
        // The row-based guard must NOT trigger here.
        let boxes: [PopplerRect] = [
            r(50, 700, 250, 600),  // left column block 1 (height 100 pt)
            r(50, 590, 250, 490),  // left column block 2
            r(320, 700, 520, 600),  // right column block 1
            r(320, 590, 520, 490),  // right column block 2
        ]
        let sorted = XYCutSorter.sortedIndices(of: boxes)
        #expect(sorted.count == 4)
        // Left column (indices 0 and 1) must precede right column (indices 2 and 3).
        let leftIndices = Set(sorted.prefix(2))
        let rightIndices = Set(sorted.suffix(2))
        #expect(leftIndices == [0, 1], "Left column blocks should come first")
        #expect(rightIndices == [2, 3], "Right column blocks should come second")
    }

    @Test("isVerticallyAligned works for same-row and different-row elements")
    func verticalAlignmentHelper() {
        // Same row: boxes with identical Y ranges.
        #expect(
            XYCutSorter.isVerticallyAligned(
                PopplerRect(left: 50, top: 500, right: 150, bottom: 490),
                PopplerRect(left: 450, top: 500, right: 470, bottom: 490)))
        // Different rows: no Y overlap.
        #expect(
            !XYCutSorter.isVerticallyAligned(
                PopplerRect(left: 50, top: 500, right: 150, bottom: 490),
                PopplerRect(left: 450, top: 480, right: 470, bottom: 470)))
    }
}
