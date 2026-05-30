import PopplerKit

// MARK: - HeaderFooterDetector
//
// Detects page headers and footers by finding LayoutTextLines whose text
// content appears (verbatim or as a sequential counter) at the same
// vertical position across ≥ 2 consecutive pages.
//
// Algorithm:
//   1. For each page, take the topmost N lines as header candidates and
//      the bottommost N lines as footer candidates (N = maxCandidateLines).
//   2. A candidate is a header/footer if the same text (or a text that
//      differs only by a page-number counter) appears at an overlapping
//      Y position on the previous or next page.
//   3. Filter by vertical zone: headers must be in the top 1/3 of the page;
//      footers in the bottom 1/3.

public enum HeaderFooterDetector {

    static let maxCandidateLines: Int = 4
    /// Maximum vertical gap (pt) allowed between successive header/footer lines.
    static let maxGap: Double = 30.0

    // MARK: - Result

    public struct Result: Sendable {
        /// For each page index, the set of line indices classified as headers.
        public let headerLineIndices: [[Int]]
        /// For each page index, the set of line indices classified as footers.
        public let footerLineIndices: [[Int]]
    }

    // MARK: - Public

    /// Detect header and footer lines across all pages.
    ///
    /// - Parameter pageLines: One array of `LayoutTextLine` per page, in top→bottom order.
    /// - Parameter pageHeights: Height of each page in PDF points.
    /// - Returns: Per-page sets of header/footer line indices.
    public static func detect(
        pageLines: [[LayoutTextLine]],
        pageHeights: [Double]
    ) -> Result {
        let n = pageLines.count
        var headerIdx = Array(repeating: [Int](), count: n)
        var footerIdx = Array(repeating: [Int](), count: n)

        for pageIndex in 0..<n {
            let lines = pageLines[pageIndex]
            let pageH = pageIndex < pageHeights.count ? pageHeights[pageIndex] : 841.0
            let topZone = pageH * 2 / 3  // header must be above this Y
            let bottomZone = pageH / 3  // footer must be below this Y

            // Header candidates: topmost lines inside the top zone
            headerIdx[pageIndex] = detectZone(
                lines: lines,
                pageIndex: pageIndex,
                allPages: pageLines,
                isHeader: true,
                zoneY: topZone
            )

            // Footer candidates: bottommost lines inside the bottom zone
            footerIdx[pageIndex] = detectZone(
                lines: lines,
                pageIndex: pageIndex,
                allPages: pageLines,
                isHeader: false,
                zoneY: bottomZone
            )
        }
        return Result(headerLineIndices: headerIdx, footerLineIndices: footerIdx)
    }

    // MARK: - Private

    private static func detectZone(
        lines: [LayoutTextLine],
        pageIndex: Int,
        allPages: [[LayoutTextLine]],
        isHeader: Bool,
        zoneY: Double
    ) -> [Int] {
        let candidates: [(index: Int, line: LayoutTextLine)]
        if isHeader {
            // Top of page: lines sorted top→bottom; take first `max` inside zone
            candidates = lines.enumerated()
                .prefix(maxCandidateLines)
                .filter {
                    isHeader
                        ? $0.element.boundingBox.bottom > zoneY
                        : $0.element.boundingBox.top < zoneY
                }
                .map { ($0.offset, $0.element) }
        } else {
            candidates = lines.enumerated()
                .suffix(maxCandidateLines)
                .filter { $0.element.boundingBox.top < zoneY }
                .map { ($0.offset, $0.element) }
        }

        guard !candidates.isEmpty else { return [] }

        // A candidate is a header/footer if matching text exists on a neighbour page
        var result = [Int]()
        for (idx, line) in candidates {
            if isRepeatedAcrossPages(
                line: line, pageIndex: pageIndex, allPages: allPages, isHeader: isHeader)
            {
                result.append(idx)
            }
        }

        // Gap filter: remove candidates that are too far from the page edge
        return gapFiltered(result, lines: lines, isHeader: isHeader)
    }

    private static func isRepeatedAcrossPages(
        line: LayoutTextLine,
        pageIndex: Int,
        allPages: [[LayoutTextLine]],
        isHeader: Bool
    ) -> Bool {
        let neighbours = [pageIndex - 1, pageIndex + 1, pageIndex - 2, pageIndex + 2]
        for nb in neighbours {
            guard nb >= 0, nb < allPages.count else { continue }
            // prefix/suffix return ArraySlice — no copy needed, we only iterate
            let nbSlice =
                isHeader
                ? allPages[nb].prefix(maxCandidateLines)
                : allPages[nb].suffix(maxCandidateLines)
            for nbLine in nbSlice {
                if linesMatch(line, nbLine) { return true }
            }
        }
        return false
    }

    /// Two lines "match" when their text is identical or differs only by
    /// a sequential integer (page-number counter).
    private static func linesMatch(_ a: LayoutTextLine, _ b: LayoutTextLine) -> Bool {
        let at = a.text.trimmingCharacters(in: .whitespaces)
        let bt = b.text.trimmingCharacters(in: .whitespaces)
        if at == bt { return true }
        // Check if texts differ only by an integer suffix (page numbers)
        if textsDifferByCounter(at, bt) { return true }
        // Check if Y positions overlap (same row on page, within 5 pt)
        let yCentreA = (a.boundingBox.top + a.boundingBox.bottom) / 2
        let yCentreB = (b.boundingBox.top + b.boundingBox.bottom) / 2
        return abs(yCentreA - yCentreB) < 5
    }

    /// Returns true when the two strings differ only by their trailing integer.
    private static func textsDifferByCounter(_ a: String, _ b: String) -> Bool {
        let trailingDigits = /\d+$/
        let aStripped = a.replacing(trailingDigits, with: "")
        let bStripped = b.replacing(trailingDigits, with: "")
        guard !aStripped.isEmpty, aStripped == bStripped else { return false }
        let aSuffix = String(a.dropFirst(aStripped.count))
        let bSuffix = String(b.dropFirst(bStripped.count))
        return Int(aSuffix) != nil && Int(bSuffix) != nil
    }

    /// Remove candidates that have too large a vertical gap from their neighbour.
    ///
    /// Coordinate convention (y-UP / PDF space): `top` > `bottom`.
    /// Elements near the page top have LARGE `top`; elements near the page bottom
    /// (footer zone) have SMALL `top`.
    ///
    /// - For **headers**: process in visual top→bottom order (decreasing `top`).
    ///   Each new candidate must be within `maxGap` of the previous confirmed header.
    ///   Gap = `prev.bottom − curr.top` (distance between lower edge of prev and upper edge of curr).
    ///
    /// - For **footers**: process from the page bottom upward (ascending `top`), starting
    ///   with the confirmed-footer element (smallest `top`).  This ensures the body text
    ///   that repeats across pages but sits above the footer zone is correctly rejected
    ///   when the gap > 30 pt — prevents body text that repeats across pages from
    ///   being absorbed into the footer region.
    ///   Gap = `curr.bottom − prev.top` (distance between lower edge of curr and upper edge of prev).
    private static func gapFiltered(_ indices: [Int], lines: [LayoutTextLine], isHeader: Bool)
        -> [Int]
    {
        guard !indices.isEmpty else { return [] }

        if isHeader {
            // Header: already in visual top→bottom order; first = nearest page top.
            var result = [Int]()
            for (pos, idx) in indices.enumerated() {
                if pos == 0 {
                    result.append(idx)
                    continue
                }
                let prev = lines[indices[pos - 1]]
                let curr = lines[idx]
                let gap = prev.boundingBox.bottom - curr.boundingBox.top
                if gap <= maxGap { result.append(idx) }
            }
            return result
        } else {
            // Footer: sort by `top` ASCENDING so we start from the page bottom
            // (smallest `top` in y-UP = visually lowest = confirmed footer line).
            let sorted = indices.sorted { lines[$0].boundingBox.top < lines[$1].boundingBox.top }
            var accepted = [Int]()
            for (pos, idx) in sorted.enumerated() {
                if pos == 0 {
                    accepted.append(idx)
                    continue
                }
                let prev = lines[sorted[pos - 1]]  // lower on page (smaller top)
                let curr = lines[idx]  // candidate above it (larger top)
                // gap = distance between curr’s lower edge and prev’s upper edge
                let gap = curr.boundingBox.bottom - prev.boundingBox.top
                if gap <= maxGap { accepted.append(idx) }
            }
            return accepted.sorted()  // restore original index order
        }
    }
}
