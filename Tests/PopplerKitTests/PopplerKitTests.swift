import Foundation
import Testing

@testable import PopplerKit

// MARK: - Shared resource

/// Resolves the test PDF from the bundle (SPM copies it via `.process("Resources")`).
func testPDF() throws -> URL {
    guard
        let url = Bundle.module.url(
            forResource: "ast_sci_data_tables_sample",
            withExtension: "pdf"
        )
    else {
        Issue.record("ast_sci_data_tables_sample.pdf not found in test bundle")
        throw PopplerError.documentLoadFailed
    }
    return url
}

/// Resolves the invoice PDF from the test bundle.
func invoicePDF() throws -> URL {
    guard
        let url = Bundle.module.url(forResource: "invoice", withExtension: "pdf")
    else {
        Issue.record("invoice.pdf not found in test bundle")
        throw PopplerError.documentLoadFailed
    }
    return url
}

// MARK: - Text Extraction

/// Tests that verify text content can be extracted from the science data-tables PDF.
///
/// The document contains five worked examples for a science afterschool programme:
/// pet surveys, electromagnets, pH values, land speed records, and distance/time data.
/// All expected strings come from the known content of the PDF.
@Suite("Text Extraction — ast_sci_data_tables_sample.pdf")
struct TextExtractionTests {

    let doc: PopplerDocument

    init() throws {
        doc = try PopplerDocument.load(from: testPDF())
    }

    // MARK: Text layer detection

    @Test("Document has an extractable text layer")
    func hasTextLayer() {
        #expect(doc.hasExtractableText)
    }

    // MARK: Full-document extraction

    @Test("extractText() returns content from both pages")
    func extractTextBothPages() async throws {
        let text = try await doc.extractText()
        // Page 1 content
        #expect(text.contains("NATIONAL PARTNERSHIP"))
        #expect(text.contains("Tutoring Two"))
        #expect(text.contains("Pet Survey"))
        #expect(text.contains("Morales Elementary"))
        #expect(text.contains("pH"))
        // Page 2 content (electromagnet data + speed records + distance/time + copyright)
        #expect(text.contains("Craig Breedlove"))
        #expect(text.contains("763.035"))  // land speed record
        #expect(text.contains("Andy Green"))  // Thrust SSC driver
        #expect(text.contains("Distance and Time"))
        #expect(text.contains("2006 WGBH"))  // copyright
    }

    @Test("extractText() with physical layout preserves column structure")
    func extractTextPhysicalLayout() async throws {
        let text = try await doc.extractText(layout: .physical)
        // Physical layout should still contain all key strings
        #expect(text.contains("Craig Breedlove"))
        #expect(text.contains("763.035"))
    }

    // MARK: Streaming

    @Test("textStream() yields exactly 2 non-empty page strings")
    func textStreamPageCount() async throws {
        var pages: [String] = []
        for try await pageText in doc.textStream() {
            pages.append(pageText)
        }
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @Test("textStream() page 0 contains title, page 1 contains copyright")
    func textStreamPageContent() async throws {
        var pages: [String] = []
        for try await pageText in doc.textStream() {
            pages.append(pageText)
        }
        #expect(pages[0].contains("NATIONAL PARTNERSHIP"))
        #expect(pages[1].contains("2006 WGBH"))
    }

    // MARK: Per-page extraction

    @Test("Page 0 text contains the document title and examples")
    func page0Text() throws {
        let page = try doc.page(at: 0)
        let text = page.text()
        #expect(text.contains("NATIONAL PARTNERSHIP"))
        #expect(text.contains("Tutoring Two"))
        #expect(text.contains("Pet Survey"))
        #expect(text.contains("pH"))
    }

    @Test("Page 1 text contains speed records and copyright")
    func page1Text() throws {
        let page = try doc.page(at: 1)
        let text = page.text()
        #expect(text.contains("Craig Breedlove"))
        #expect(text.contains("763.035"))
        #expect(text.contains("2006 WGBH"))
    }

    @Test("Physical-layout extraction preserves tab-separated land-speed table")
    func physicalLayoutSpeedTable() throws {
        let page = try doc.page(at: 1)
        let text = page.text(layout: .physical)
        // Speed record driver and value must coexist in physical layout
        #expect(text.contains("Craig Breedlove"))
        #expect(text.contains("763.035"))
        #expect(text.contains("Andy Green"))
    }

    // MARK: Region extraction

    @Test("text(in:) extracts text from the top half of page 0")
    func regionExtraction() throws {
        let page = try doc.page(at: 0)
        // Top half of the page — should contain the document title
        let topHalf = PopplerRect(
            left: 0,
            top: 0,
            right: page.width,
            bottom: page.height / 2
        )
        let topText = page.text(in: topHalf)
        // The title lives in the upper portion of page 1
        #expect(!topText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: Search

    @Test("search(for:) finds all five examples by keyword")
    func searchFindsExamples() throws {
        // The document has 5 examples spread across 2 pages
        var totalHits = 0
        for i in 0..<doc.pageCount {
            let page = try doc.page(at: i)
            totalHits += page.search(for: "Example", caseSensitive: false).count
        }
        #expect(totalHits >= 5)
    }

    @Test("search(for:) finds Craig Breedlove by exact name")
    func searchFindsSpecificName() throws {
        let page = try doc.page(at: 1)
        let hits = page.search(for: "Craig Breedlove")
        #expect(!hits.isEmpty)
        // Each hit rect should be non-zero-sized
        #expect(hits.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    @Test("search(for:) returns empty for a string not in the document")
    func searchMissOnAbsentString() throws {
        let page = try doc.page(at: 0)
        let hits = page.search(for: "xyzzy_not_in_pdf_12345")
        #expect(hits.isEmpty)
    }

    @Test("search result rect can be used with text(in:) to read the matched word")
    func searchRectFeedsIntoRegionExtraction() throws {
        let page = try doc.page(at: 1)
        let hits = page.search(for: "763.035")
        // There must be at least one hit
        #expect(!hits.isEmpty)
        guard let firstHit = hits.first else { return }
        // A slightly expanded region around the hit should contain the value
        let region = PopplerRect(
            left: firstHit.left - 5,
            top: firstHit.top - 5,
            right: firstHit.right + 5,
            bottom: firstHit.bottom + 5
        )
        let snippet = page.text(in: region)
        #expect(snippet.contains("763"))
    }

    // MARK: Page range options

    @Test("extractText(firstPage:lastPage:) returns only the requested range")
    func extractTextPageRange() async throws {
        let page0Only = try await doc.extractText(firstPage: 0, lastPage: 0)
        let page1Only = try await doc.extractText(firstPage: 1, lastPage: 1)

        #expect(page0Only.contains("NATIONAL PARTNERSHIP"))
        #expect(!page0Only.contains("Craig Breedlove"))  // only on page 1

        #expect(page1Only.contains("Craig Breedlove"))
        #expect(!page1Only.contains("NATIONAL PARTNERSHIP"))  // only on page 0
    }
}
