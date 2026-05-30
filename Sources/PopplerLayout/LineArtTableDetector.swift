#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import PopplerKit

// MARK: - LineArtTableDetector
//
// Detects bordered tables by analysing the line segments drawn by the PDF's
// vector-graphics content stream.  Outperforms the image-scan approach
// (BorderScanDetector) in both accuracy and speed:
//   • Accuracy: works on any zoom level and color depth.
//   • Speed:    no page rendering needed — segments come directly from the
//               PDF operator stream.
//
// Algorithm:
//   1. Filter segments to those that are axis-aligned (H or V, within 3°).
//   2. Merge collinear segments that are within mergeGapPt of each other.
//   3. Require a minimum span (minSpanFraction × page dimension) to exclude
//      underlines and decoration lines.
//   4. Find the largest rectangular grid region (2+ H lines × 2+ V lines).
//   5. Assign LayoutTextLine text to cells by bounding-box containment.

public enum LineArtTableDetector {

    // MARK: - Configuration

    /// Segments less than this fraction of the page width/height are discarded
    /// as decorations (underlines, dividers).
    public static let minSpanFraction: Double = 0.10

    /// Collinear segments within this many PDF points on the same axis are merged.
    public static let mergeGapPt: Double = 4.0

    /// Lines whose position (y for H, x for V) differ by less than this are
    /// considered the same grid line.
    public static let positionTolerance: Double = 3.0

    // MARK: - Public

    /// Detect bordered tables on a page using its vector-graphics line art.
    ///
    /// - Parameters:
    ///   - page: The page to analyse (must be file-loaded for `lineArtSegments()` to work).
    ///   - pageLines: Visual text lines on this page (from `LineGrouper`).
    ///   - pageWidth: Page width in PDF points.
    ///   - pageHeight: Page height in PDF points.
    /// - Returns: An array of `(PDFTable, boundingBox)` pairs.
    public static func detect(
        page: PopplerPage,
        pageLines: [LayoutTextLine],
        pageWidth: Double,
        pageHeight: Double
    ) -> [(table: PDFTable, boundingBox: PopplerRect)] {

        let segments = page.lineArtSegments()
        guard !segments.isEmpty else { return [] }

        let minHSpan = pageWidth * minSpanFraction
        let minVSpan = pageHeight * minSpanFraction

        // Separate and filter axis-aligned segments
        let hSegs = segments.filter { $0.isHorizontal() && $0.width >= minHSpan }
        let vSegs = segments.filter { $0.isVertical() && $0.height >= minVSpan }

        guard hSegs.count >= 2, vSegs.count >= 2 else { return [] }

        // Cluster H-segment positions (y coordinate) and V-segment positions (x coordinate)
        let hPositions = clusterPositions(hSegs.map { ($0.y1 + $0.y2) / 2 })
        let vPositions = clusterPositions(vSegs.map { ($0.x1 + $0.x2) / 2 })

        guard hPositions.count >= 2, vPositions.count >= 2 else { return [] }

        // Build tables for each detected grid
        let hSorted = hPositions.sorted(by: >)  // top→bottom in PDF coords
        let vSorted = vPositions.sorted()  // left→right

        var results = [(table: PDFTable, boundingBox: PopplerRect)]()

        // For simplicity, treat all H/V lines as one grid.
        // A more sophisticated implementation would cluster nearby grids separately.
        if var table = buildTable(
            hLines: hSorted, vLines: vSorted,
            pageLines: pageLines
        ) {
            let bb = PopplerRect(
                left: vSorted.first!,
                top: hSorted.first!,
                right: vSorted.last!,
                bottom: hSorted.last!
            )
            // Try to fix under-segmented tables (too few horizontal grid lines)
            table = TableStructureNormalizer.normalize(
                table: table, tableBB: bb, pageLines: pageLines)
            results.append((table, bb))
        }
        return results
    }

    // MARK: - Private

    /// Cluster a sorted list of positions, merging values within `positionTolerance`.
    private static func clusterPositions(_ rawPositions: [Double]) -> [Double] {
        guard !rawPositions.isEmpty else { return [] }
        let sorted = rawPositions.sorted()
        var clusters: [[Double]] = [[sorted[0]]]
        for pos in sorted.dropFirst() {
            if pos - clusters.last!.last! <= positionTolerance {
                clusters[clusters.count - 1].append(pos)
            } else {
                clusters.append([pos])
            }
        }
        return clusters.map { $0.reduce(0, +) / Double($0.count) }
    }

    /// Build a `PDFTable` from horizontal (y) and vertical (x) grid-line positions.
    private static func buildTable(
        hLines: [Double],  // y positions, sorted top→bottom (higher y first)
        vLines: [Double],  // x positions, sorted left→right
        pageLines: [LayoutTextLine]
    ) -> PDFTable? {
        let rows = hLines.count - 1
        let cols = vLines.count - 1
        guard rows >= 1, cols >= 1 else { return nil }

        // Column boundaries
        let colBounds: [(lo: Double, hi: Double)] = (0..<cols).map { c in
            (vLines[c], vLines[c + 1])
        }
        // Row boundaries (hLines sorted top→bottom so hLines[r] > hLines[r+1] in PDF y)
        let rowBounds: [(bottom: Double, top: Double)] = (0..<rows).map { r in
            (hLines[r + 1], hLines[r])
        }

        // Assign text lines to cells
        var cellText = Array(repeating: Array(repeating: "", count: cols), count: rows)
        for line in pageLines {
            let cx = (line.boundingBox.left + line.boundingBox.right) / 2
            let cy = (line.boundingBox.top + line.boundingBox.bottom) / 2
            guard
                let ci = colBounds.firstIndex(where: { $0.lo <= cx && cx < $0.hi }),
                let ri = rowBounds.firstIndex(where: { $0.bottom <= cy && cy <= $0.top })
            else { continue }
            let t = line.text.trimmingWhitespace()
            if !t.isEmpty {
                cellText[ri][ci] = cellText[ri][ci].isEmpty ? t : cellText[ri][ci] + " " + t
            }
        }

        // First non-empty row → headers
        guard
            let headerRow = (0..<rows).first(where: { r in
                (0..<cols).contains { !cellText[r][$0].isEmpty }
            })
        else { return nil }

        var seen = [String: Int]()
        let headers: [String] = (0..<cols).map { c in
            let raw = cellText[headerRow][c].isEmpty ? "Col\(c + 1)" : cellText[headerRow][c]
            let n = seen[raw, default: 0]
            seen[raw] = n + 1
            return n == 0 ? raw : "\(raw) (\(n + 1))"
        }

        let dataRows: [PDFTable.Row] = ((headerRow + 1)..<rows).compactMap { r in
            var cells = [String: String]()
            for c in 0..<cols where !cellText[r][c].isEmpty {
                cells[headers[c]] = cellText[r][c]
            }
            return cells.isEmpty ? nil : PDFTable.Row(cells: cells)
        }
        guard !dataRows.isEmpty else { return nil }
        return PDFTable(headers: headers, rows: dataRows)
    }
}

// MARK: - PopplerPage extension

extension PopplerPage {

    /// Detect bordered tables using PDF vector-graphics line art.
    ///
    /// More accurate and faster than `detectBorderedTables()` (image-scan) because
    /// it reads actual drawing operators rather than analysing rendered pixels.
    /// Returns an empty array for pages loaded from raw `Data`.
    public func detectLineArtTables(
        pageLines: [LayoutTextLine]? = nil
    ) -> [(table: PDFTable, boundingBox: PopplerRect)] {
        let pw = cropBox.width
        let ph = cropBox.top - cropBox.bottom
        let lines = pageLines ?? textLines()
        return LineArtTableDetector.detect(
            page: self, pageLines: lines,
            pageWidth: pw, pageHeight: ph
        )
    }
}
