#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import PopplerKit

// MARK: - LayoutAnalyzer
//
// Orchestrates the full layout analysis pipeline:
//
//   1. textBoxes()          — raw text boxes from poppler
//   2. XYCutSorter          — reading-order sort
//   3. LineGrouper          — boxes → visual lines
//   4. HeaderFooterDetector — cross-page chrome detection (document level)
//   5. HeadingDetector      — font-statistics based heading classification
//   6. ListDetector         — label prefix detection
//   7. AutoTableDetector    — geometry-based table detection
//   8. Emit PopplerLayoutElement stream

// MARK: - PopplerPage extension

extension PopplerPage {

    /// Extract visual text lines from this page in reading order.
    ///
    /// - Parameter sortReadingOrder: When `true` (default), applies XY-Cut++
    ///   sorting before grouping — corrects reading order for multi-column layouts.
    public func textLines(sortReadingOrder: Bool = true) -> [LayoutTextLine] {
        let boxes = textBoxes()
        let ordered: [PopplerTextBox]
        if sortReadingOrder {
            let rects = boxes.map(\.boundingBox)
            let indices = XYCutSorter.sortedIndices(of: rects)
            ordered = indices.map { boxes[$0] }
        } else {
            ordered = boxes
        }
        return LineGrouper.group(ordered)
    }

    /// Detect tables on this page without requiring header keywords.
    ///
    /// Uses bounding-box column/row clustering; more robust than the
    /// keyword-based `extractTable(headerKeywords:)` for unknown table layouts.
    public func detectTables(pageWidth: Double? = nil) -> [PDFTable] {
        let width = pageWidth ?? cropBox.width
        let ph = cropBox.top - cropBox.bottom
        let lines = textLines()

        // Prefer line-art detection (accurate, fast) over geometry clustering.
        let lineArtResults = LineArtTableDetector.detect(
            page: self, pageLines: lines, pageWidth: width, pageHeight: ph)
        if !lineArtResults.isEmpty { return lineArtResults.map(\.table) }

        // Fall back to geometry-based detection (no line art in document).
        return AutoTableDetector.detect(lines: lines, pageWidth: width).map(\.table)
    }
}

// MARK: - PopplerDocument extension

extension PopplerDocument {

    // MARK: - Full-document layout extraction

    /// Extract structured layout elements from the entire document.
    ///
    /// Returns one array of `PopplerLayoutElement` per page, processed with:
    /// - XY-Cut++ reading-order correction
    /// - Cross-page header/footer removal
    /// - Heading level detection (document-wide font statistics)
    /// - Automatic list detection
    /// - Automatic table detection
    ///
    /// ```swift
    /// let layout = try await doc.extractLayout()
    /// for (pageIndex, elements) in layout.enumerated() {
    ///     for element in elements {
    ///         switch element {
    ///         case .heading(let lvl, let text, _, _): print("H\(lvl): \(text)")
    ///         case .paragraph(let text, _):           print(text)
    ///         case .table(let tbl, _):                print(tbl.rows.count, "rows")
    ///         case .header, .footer:                  break
    ///         }
    ///     }
    /// }
    /// ```
    public func extractLayout() async throws -> [[PopplerLayoutElement]] {
        // 1. Collect text lines per page (with XY-Cut++ sort)
        let allPageLines: [[LayoutTextLine]] = try await withThrowingTaskGroup(
            of: (Int, [LayoutTextLine]).self
        ) { group in
            for i in 0..<pageCount {
                group.addTask { [self] in
                    let pg = try self.page(at: i)
                    var lines = pg.textLines(sortReadingOrder: true)
                    // Strip invisible (mode-3) text — common prompt-injection vector
                    let (filtered, _) = HiddenTextFilter.filter(lines: lines, page: pg)
                    lines = filtered
                    return (i, lines)
                }
            }
            var result = Array(repeating: [LayoutTextLine](), count: pageCount)
            for try await (i, lines) in group { result[i] = lines }
            return result
        }

        // 2. Page dimensions for header/footer zone thresholds
        let pageHeights: [Double] = (0..<pageCount).compactMap { i in
            try? page(at: i).mediaBox.top - page(at: i).mediaBox.bottom
        }

        // 3. Header/footer detection (cross-page, sequential)
        let hfResult = HeaderFooterDetector.detect(
            pageLines: allPageLines,
            pageHeights: pageHeights
        )

        // 4. Document-wide heading detection
        let headingFlags = HeadingDetector.detectHeadings(in: allPageLines)
        let sizeToLevel = HeadingDetector.headingLevels(
            in: allPageLines, isHeading: headingFlags)

        // 5. Assemble elements per page
        return allPageLines.enumerated().map { (pi, lines) in
            let pg = try? page(at: pi)
            let pw = pg?.cropBox.width ?? 595
            let ph = pg.map { $0.cropBox.top - $0.cropBox.bottom } ?? 841

            // Table detection priority:
            //   1. LineArtTableDetector  — PDF drawing operators (most accurate)
            //   2. BorderScanDetector    — rendered-image pixel scan (fallback)
            let lineArtTables =
                pg.map {
                    LineArtTableDetector.detect(
                        page: $0, pageLines: lines, pageWidth: pw, pageHeight: ph)
                } ?? []
            let borderedTables =
                lineArtTables.isEmpty
                ? (pg?.detectBorderedTables() ?? [])
                : lineArtTables.map(\.table)

            return assembleElements(
                lines: lines,
                pageIndex: pi,
                pageWidth: pw,
                headerIndices: Set(hfResult.headerLineIndices[pi]),
                footerIndices: Set(hfResult.footerLineIndices[pi]),
                isHeading: headingFlags[pi],
                sizeToLevel: sizeToLevel,
                borderedTables: borderedTables
            )
        }
    }

    // MARK: - Convenience

    /// Returns the document body text, reading-order corrected, with page headers/footers
    /// optionally stripped.
    ///
    /// Unlike `PopplerDocument.extractText(layout:...)` (which wraps poppler's built-in text
    /// extractor), this method runs the full `PopplerLayout` pipeline — XY-Cut++ reading order,
    /// header/footer detection, and heading/list/table structure — before joining the text.
    ///
    /// - Parameter removeChrome: When `true` (default), page headers and footers are omitted.
    public func extractLayoutText(removeChrome: Bool = true) async throws -> String {
        let layout = try await extractLayout()
        return layout.flatMap { pageElements in
            pageElements.compactMap { element -> String? in
                if removeChrome, element.isChrome { return nil }
                let t = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
        }.joined(separator: "\n\n")
    }

    // MARK: - Private assembly

    private func assembleElements(
        lines: [LayoutTextLine],
        pageIndex: Int,
        pageWidth: Double,
        headerIndices: Set<Int>,
        footerIndices: Set<Int>,
        isHeading: [Bool],
        sizeToLevel: [Double: Int],
        borderedTables: [PDFTable] = []
    ) -> [PopplerLayoutElement] {

        // Detect tables by two methods:
        //   • AutoTableDetector (geometry) — has precise line ranges; consumed lines are skipped.
        //   • BorderScanDetector (image)   — bbox-based; lines are NOT consumed so that
        //     headings/paragraphs co-located with the table still render correctly.
        let geoHits = AutoTableDetector.detect(lines: lines, pageWidth: pageWidth)

        // Lines consumed by geometry-detected tables.
        // Heading lines are never consumed — a widely-spaced heading can look tabular
        // to the column-clustering algorithm but must remain classified as a heading.
        var consumedByTable = Set<Int>()
        for hit in geoHits {
            for li in hit.lineRange {
                guard li >= isHeading.count || !isHeading[li] else { continue }
                consumedByTable.insert(li)
            }
        }

        var elements = [PopplerLayoutElement]()

        // Emit border-detected tables first (at the top of the element list) when geometry
        // found nothing — they supplement rather than replace line classification.
        if geoHits.isEmpty {
            for tbl in borderedTables {
                // Compute bounding box from the lines whose centres fall inside the table
                // (we don't have a line range, so we approximate with the full page)
                let left = lines.map { $0.boundingBox.left }.min() ?? 0
                let top = lines.map { $0.boundingBox.top }.max() ?? 0
                let right = lines.map { $0.boundingBox.right }.max() ?? 0
                let bottom = lines.map { $0.boundingBox.bottom }.min() ?? 0
                let bb = PopplerRect(left: left, top: top, right: right, bottom: bottom)
                elements.append(.table(tbl, boundingBox: bb))
            }
        }

        var tableQueue = geoHits.sorted { $0.lineRange.lowerBound < $1.lineRange.lowerBound }

        for (li, line) in lines.enumerated() {
            // Emit a geometry-detected table when we reach its start line
            if let first = tableQueue.first, first.lineRange.lowerBound == li {
                tableQueue.removeFirst()
                let bb = unionBoundingBox(lines: lines, range: first.lineRange)
                elements.append(.table(first.table, boundingBox: bb))
            }
            if consumedByTable.contains(li) { continue }

            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let bb = line.boundingBox

            if headerIndices.contains(li) {
                elements.append(.header(text: text, boundingBox: bb))
            } else if footerIndices.contains(li) {
                elements.append(.footer(text: text, boundingBox: bb))
            } else if li < isHeading.count && isHeading[li] {
                let sz = (line.fontSize * 2).rounded() / 2
                // Clamp to H1–H6: levels outside this range have no Markdown or
                // accessibility meaning (WCAG 2.x, CommonMark spec §4.2).
                let level = min(6, max(1, sizeToLevel[sz] ?? 1))
                elements.append(
                    .heading(level: level, text: text, boundingBox: bb, fontSize: line.fontSize))
            } else if CaptionDetector.isCaption(line) {
                elements.append(.caption(text: text, boundingBox: bb))
            } else if let items = ListDetector.splitMultipleItems(in: line) {
                // Multiple labeled segments were merged into one LayoutTextLine.
                // Emit each as its own list item (restored to individual elements).
                for item in items {
                    elements.append(
                        .listItem(
                            label: item.label, text: item.body, boundingBox: bb,
                            nestingLevel: 1))
                }
            } else if let listItem = ListDetector.detectItem(in: line) {
                elements.append(
                    .listItem(
                        label: listItem.label, text: listItem.body, boundingBox: bb,
                        nestingLevel: 1))  // level assigned below by LevelDetector
            } else {
                elements.append(.paragraph(text: text, boundingBox: bb))
            }
        }
        // Assign nesting levels to list items based on indentation
        return LevelDetector.detectNesting(elements)
    }

    private func unionBoundingBox(lines: [LayoutTextLine], range: Range<Int>) -> PopplerRect {
        let slice = lines[range]
        let left = slice.map(\.boundingBox.left).min() ?? 0
        let right = slice.map(\.boundingBox.right).max() ?? 0
        let top = slice.map(\.boundingBox.top).max() ?? 0
        let bottom = slice.map(\.boundingBox.bottom).min() ?? 0
        return PopplerRect(left: left, top: top, right: right, bottom: bottom)
    }
}

// MARK: - ListDetector (internal)

enum ListDetector {
    struct ListItem {
        let label: String?
        let body: String
    }

    // Matches a list-label prefix at the start of a string.
    // Capture group 1 is the label (bullet or number/letter marker + trailing space).
    nonisolated(unsafe) private static let labelRegex =
        #/^(\s*(?:[•·▪▸▹◦‣⁃]|\d{1,3}[.):]|[a-zA-Z][.)]|[①-⑳]|[㉠-㉻]|[(][^)]{1,5}[)])\s+)/#

    // Matches strings that consist entirely of space-separated decimal numbers
    // such as "1.5 2.3 3.7" — these must not be treated as labeled list items.
    nonisolated(unsafe) private static let doublesRegex = #/^\d+\.\d+(\s+\d+\.\d+)*$/#

    // MARK: Single-line detection

    static func detectItem(in line: LayoutTextLine) -> ListItem? {
        let text = line.text
        guard let match = text.firstMatch(of: labelRegex) else { return nil }
        // trimmingCharacters(in:) on StringProtocol already returns String — no String() copy needed
        let label = match.output.1.trimmingCharacters(in: .whitespaces)
        let body = text[match.range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        return ListItem(label: label, body: body)
    }

    // MARK: Multi-item split
    //
    // When a single LayoutTextLine contains multiple labeled segments — because
    // poppler merged tightly-spaced list items into one extraction unit — this
    // splits it into individual ListItems so each gets its own .listItem element.
    //
    // Algorithm (per-box):
    //   1. Walk line.boxes; check each box's text for a label prefix.
    //   2. If fewer than 2 boxes are labeled → return nil  (restore guard).
    //   3. Doubles guard: if the full text matches space-separated decimals → return nil.
    //   4. Accumulate: each labeled box starts a new item; unlabeled boxes
    //      following it are treated as continuation text for that item.
    //   5. Return nil unless at least 2 items were produced.
    static func splitMultipleItems(in line: LayoutTextLine) -> [ListItem]? {
        guard line.boxes.count >= 2 else { return nil }

        let labeledCount = line.boxes.filter { labelPrefix(in: $0.text) != nil }.count
        guard labeledCount >= 2 else { return nil }

        let fullText = line.text.trimmingCharacters(in: .whitespaces)
        if fullText.wholeMatch(of: doublesRegex) != nil { return nil }

        var items = [ListItem]()
        var curLabel: String? = nil
        var curBody = [String]()

        func flush() {
            guard let lbl = curLabel else { return }
            let body = curBody.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !body.isEmpty { items.append(ListItem(label: lbl, body: body)) }
        }

        for box in line.boxes {
            let t = box.text.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if let lbl = labelPrefix(in: t) {
                flush()
                curLabel = lbl
                if let match = t.firstMatch(of: labelRegex) {
                    let remainder = t[match.range.upperBound...]
                        .trimmingCharacters(in: .whitespaces)
                    curBody = remainder.isEmpty ? [] : [remainder]
                } else {
                    curBody = []
                }
            } else {
                curBody.append(t)
            }
        }
        flush()

        return items.count >= 2 ? items : nil
    }

    /// Returns the label prefix if `text` starts with a list-label pattern, else `nil`.
    private static func labelPrefix(in text: String) -> String? {
        guard let match = text.firstMatch(of: labelRegex) else { return nil }
        return match.output.1.trimmingCharacters(in: .whitespaces)
    }
}
