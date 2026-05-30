import Foundation
import Testing

@testable import PopplerKit

// MARK: - Document API, TextBoxes, Rendering & Concurrency

/// Tests that verify document-level properties, word-level coordinate extraction,
/// rendering, and concurrent access on the science data-tables PDF.
@Suite("Document API — ast_sci_data_tables_sample.pdf")
struct DocumentAPITests {

    let doc: PopplerDocument

    init() throws {
        doc = try PopplerDocument.load(from: testPDF())
    }

    // MARK: Structure

    @Test("Page count is 2")
    func pageCount() {
        #expect(doc.pageCount == 2)
    }

    @Test("Page dimensions are reasonable (US Letter: ~612 × 792 pt)")
    func pageDimensions() throws {
        let page = try doc.page(at: 0)
        // US Letter = 612 × 792 PDF points; allow ±5 pt for producer rounding
        #expect(page.cropBox.width > 600 && page.cropBox.width < 620)
        #expect(page.cropBox.height > 780 && page.cropBox.height < 800)
        // mediaBox should be at least as large as cropBox
        #expect(page.mediaBox.width >= page.cropBox.width - 1)
        #expect(page.mediaBox.height >= page.cropBox.height - 1)
    }

    @Test("Both pages have consistent dimensions")
    func bothPagesHaveDimensions() throws {
        let p0 = try doc.page(at: 0)
        let p1 = try doc.page(at: 1)
        #expect(abs(p0.width - p1.width) < 5)
        #expect(abs(p0.height - p1.height) < 5)
    }

    // MARK: Security & metadata

    @Test("Not encrypted, not restricted, no form or JS")
    func notRestrictedOrEncrypted() {
        #expect(!doc.isEncrypted)
        #expect(!doc.isLocked)
        let perms = doc.permissions
        #expect(perms.contains(.print))
        #expect(perms.contains(.copy))
        #expect(perms.contains(.change))
        #expect(perms.contains(.fillForms))
        #expect(perms.contains(.accessibility))
        #expect(doc.formType == .none)
        #expect(!doc.hasJavaScript)
    }

    @Test("PDF version is a recognised 1.x value")
    func pdfVersion() {
        let v = doc.pdfVersion
        #expect(v.major == 1)
        #expect(v.minor >= 0 && v.minor <= 9)
    }

    // MARK: Fonts

    @Test("Document references fonts with non-empty names")
    func fontsHaveNames() {
        let fonts = doc.fonts()
        #expect(!fonts.isEmpty)
        #expect(fonts.allSatisfy { !$0.name.isEmpty })
    }

    // MARK: TextBoxes

    @Test("textBoxes() returns word-level boxes with valid coordinates")
    func textBoxCoordinates() throws {
        let page = try doc.page(at: 0)
        let boxes = page.textBoxes()
        #expect(!boxes.isEmpty)
        for box in boxes {
            // Bounding box must be inside the page
            #expect(box.boundingBox.left >= 0)
            #expect(box.boundingBox.top >= 0)
            #expect(box.boundingBox.right <= page.mediaBox.width + 5)
            #expect(box.boundingBox.bottom <= page.mediaBox.height + 5)
            // Width and height must be positive
            #expect(box.boundingBox.width > 0)
            #expect(box.boundingBox.height > 0)
        }
    }

    @Test("textBoxes() includes boxes for known words")
    func textBoxesContainKnownWords() throws {
        let page = try doc.page(at: 0)
        let texts = page.textBoxes().map(\.text)
        // "NATIONAL", "PARTNERSHIP", "Tutoring" etc. must appear as individual boxes
        let allWords = texts.joined(separator: " ")
        #expect(allWords.contains("NATIONAL") || allWords.contains("National"))
        #expect(allWords.contains("Tutoring"))
    }

    @Test("textBoxes() boxes have font info on this text-layer PDF")
    func textBoxesFontInfo() throws {
        let page = try doc.page(at: 0)
        let boxes = page.textBoxes().filter { $0.fontName != nil }
        // At least some boxes should have font metadata
        #expect(!boxes.isEmpty)
        #expect(boxes.allSatisfy { $0.fontSize > 0 })
    }

    @Test("charBBoxes count matches UCS4 code-point count of box text")
    func charBBoxCount() throws {
        let page = try doc.page(at: 0)
        let boxes = page.textBoxes().filter { !$0.text.isEmpty && !$0.charBBoxes.isEmpty }
        #expect(!boxes.isEmpty)
        // charBBoxes count should roughly match the number of Unicode scalars
        // (may differ for ligatures/combining characters — allow a tolerance)
        for box in boxes.prefix(20) {
            let scalarCount = box.text.unicodeScalars.count
            let bboxCount = box.charBBoxes.count
            // bboxCount is UCS4 code points; scalarCount should be the same or close
            #expect(
                abs(bboxCount - scalarCount) <= 2,
                "\"\(box.text)\": \(bboxCount) charBBoxes vs \(scalarCount) scalars")
        }
    }

    // MARK: Rendering

    @Test("PopplerRenderer renders page 0 to a non-empty raw pixel buffer")
    func renderRawBuffer() throws {
        let renderer = PopplerRenderer()
        let page = try doc.page(at: 0)
        let image = renderer.render(page: page, xres: 72, yres: 72)
        #expect(image != nil)
        #expect((image?.data.count ?? 0) > 0)
        #expect((image?.width ?? 0) > 0)
        #expect((image?.height ?? 0) > 0)
    }

    @Test("Pages render to non-empty data")
    func pagesRenderToData() async throws {
        let renderer = PopplerRenderer()
        renderer.setAntialiasing(true)
        for i in 0..<doc.pageCount {
            let page = try doc.page(at: i)
            let data = renderer.renderToData(page: page, xres: 72, format: .png)
            #expect(data != nil, "Page \(i) render returned nil")
            #expect((data?.count ?? 0) > 0, "Page \(i) render returned empty Data")
        }
        let pages = try await doc.rasterize(xres: 72, format: .png)
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { !$0.isEmpty })
    }

    // MARK: Concurrency — shared document

    @Test("withConcurrentPages processes all pages and returns in order")
    func concurrentPagesOrdering() async throws {
        let texts = try await doc.withConcurrentPages { page, _ in
            page.text()
        }
        #expect(texts.count == 2)
        // Results must be in page-index order regardless of task scheduling
        #expect(texts[0].contains("NATIONAL PARTNERSHIP"))
        #expect(texts[1].contains("Craig Breedlove"))
    }

    @Test("Shared PopplerRenderer is safe across concurrent tasks")
    func sharedRendererConcurrent() async throws {
        let renderer = PopplerRenderer()  // shared — Mutex-protected
        renderer.setAntialiasing(true)

        let images = try await doc.withConcurrentPages { page, _ in
            renderer.renderToData(page: page, xres: 72, format: .png)
        }
        #expect(images.count == 2)
        #expect(images.allSatisfy { $0 != nil && !($0!.isEmpty) })
    }

    @Test("Shared PopplerPage is safe across concurrent tasks")
    func sharedPageConcurrent() async throws {
        let page = try doc.page(at: 0)  // one page shared by both tasks

        async let t1 = Task { page.text() }
        async let t2 = Task { page.textBoxes().count }

        let text = await t1.value
        let count = await t2.value

        #expect(text.contains("NATIONAL PARTNERSHIP"))
        #expect(count > 0)
    }

    @Test("Concurrent render + text on the same shared page does not race")
    func sharedPageRenderAndTextConcurrent() async throws {
        let page = try doc.page(at: 0)
        let renderer = PopplerRenderer()
        renderer.setAntialiasing(true)

        let n = 30  // enough tasks to expose a race if one exists
        let results = try await withThrowingTaskGroup(of: (Bool, Bool).self) { group in
            for _ in 0..<n {
                group.addTask {
                    // Mix both operations on the SAME page instance.
                    let hasText = !page.text().isEmpty
                    let hasImage = renderer.renderToData(page: page, xres: 36) != nil
                    return (hasText, hasImage)
                }
            }
            var out: [(Bool, Bool)] = []
            for try await pair in group { out.append(pair) }
            return out
        }

        #expect(results.count == n)
        #expect(results.allSatisfy { $0.0 }, "Every task should extract non-empty text")
        #expect(results.allSatisfy { $0.1 }, "Every task should produce a rendered image")
    }

    // MARK: Document structure

    @Test("No embedded files in this simple educational PDF")
    func noEmbeddedFiles() {
        #expect(doc.embeddedFiles().isEmpty)
    }

    @Test("No table of contents in this simple educational PDF")
    func noTOC() {
        #expect(doc.tableOfContents() == nil)
    }

    @Test("pages AsyncSequence iterates both pages in order")
    func asyncPagesSequence() async throws {
        var collected: [String] = []
        for try await page in doc.pages {
            collected.append(page.text())
        }
        #expect(collected.count == 2)
        #expect(collected[0].contains("NATIONAL PARTNERSHIP"))
        #expect(collected[1].contains("Craig Breedlove"))
    }
}
