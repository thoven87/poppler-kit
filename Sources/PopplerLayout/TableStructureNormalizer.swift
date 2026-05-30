#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import PopplerKit

// MARK: - TableStructureNormalizer
//
// When LineArtTableDetector detects a table with very few rows (≤ 2) but the
// page contains many text lines inside the table's bounds, the drawn horizontal
// borders are probably only the outer/header lines and don't mark every data row.
//
// This normalizer re-infers row boundaries from the Y positions of text lines
// that fall within the table's horizontal extent, then rebuilds the PDFTable.
//
// Uses text-line Y clustering to infer row boundaries instead of relying on
// drawn horizontal grid lines, which are sometimes absent in exported PDFs.

public enum TableStructureNormalizer {

    // MARK: - Configuration

    /// A table must have ≤ this many detected rows before normalization is attempted.
    static let maxRowsToNormalize: Int = 2
    /// A table must have ≥ this many columns before normalization is attempted.
    static let minColumnsToNormalize: Int = 3
    /// Each column must contain ≥ this many text lines to qualify for normalization.
    static let minLinesPerDenseColumn: Int = 4
    /// At least this many columns must be "dense" (contain ≥ minLinesPerDenseColumn lines).
    static let minDenseColumns: Int = 2
    /// Y-clustering tolerance in PDF points — lines within this gap are in the same row.
    static let rowClusterTolerancePt: Double = 6.0

    // MARK: - Public

    /// Try to normalize `table` using text-line positions from `pageLines`.
    ///
    /// Returns the original table unchanged when normalization conditions are not met or
    /// when the rebuilt table would be lower quality.
    ///
    /// - Parameters:
    ///   - table:     The table to normalize (from LineArtTableDetector).
    ///   - tableBB:   Bounding box of the table in the page's coordinate system.
    ///   - pageLines: All visual text lines on the page.
    /// - Returns: The normalized table, or `table` if normalization was not applied.
    public static func normalize(
        table: PDFTable,
        tableBB: PopplerRect,
        pageLines: [LayoutTextLine]
    ) -> PDFTable {

        // Pre-conditions
        guard table.rows.count <= maxRowsToNormalize,
            table.headers.count >= minColumnsToNormalize
        else { return table }

        // Collect lines inside the table bounds
        let innerLines = pageLines.filter { line in
            let cx = (line.boundingBox.left + line.boundingBox.right) / 2
            let cy = (line.boundingBox.top + line.boundingBox.bottom) / 2
            return cx >= tableBB.left && cx <= tableBB.right
                && cy <= tableBB.top && cy >= tableBB.bottom
        }
        guard !innerLines.isEmpty else { return table }

        // Column x-boundaries from original header count
        let colCount = table.headers.count
        let colWidth = (tableBB.right - tableBB.left) / Double(colCount)
        let colBounds: [(lo: Double, hi: Double)] = (0..<colCount).map { c in
            (
                tableBB.left + Double(c) * colWidth,
                tableBB.left + Double(c + 1) * colWidth
            )
        }

        // Count lines per column
        var linesPerColumn = Array(repeating: [LayoutTextLine](), count: colCount)
        for line in innerLines {
            let cx = (line.boundingBox.left + line.boundingBox.right) / 2
            if let ci = colBounds.firstIndex(where: { $0.lo <= cx && cx < $0.hi }) {
                linesPerColumn[ci].append(line)
            }
        }

        let denseCount = linesPerColumn.filter { $0.count >= minLinesPerDenseColumn }.count
        guard denseCount >= minDenseColumns else { return table }

        // Cluster all inner-line Y centres into row bands
        let yCentres =
            innerLines
            .map { ($0.boundingBox.top + $0.boundingBox.bottom) / 2 }
            .sorted(by: >)  // top → bottom (y-UP: descending)
        let rowBands = clusterY(yCentres)

        // Only normalize if we found more rows than the original detection
        guard rowBands.count > table.rows.count + 1 else { return table }

        // Build new row bounds  (pairs: top > bottom in y-UP convention)
        let rowBandsSorted = rowBands.sorted(by: >)  // highest Y first = visual top
        let rowTopEdges: [Double]
        let rowBottomEdges: [Double]
        do {
            var tops = [Double]()
            var bottoms = [Double]()
            for (i, bandY) in rowBandsSorted.enumerated() {
                let t = i == 0 ? tableBB.top : (rowBandsSorted[i - 1] + bandY) / 2
                let b =
                    i == rowBandsSorted.count - 1
                    ? tableBB.bottom
                    : (bandY + rowBandsSorted[i + 1]) / 2
                tops.append(t)
                bottoms.append(b)
            }
            rowTopEdges = tops
            rowBottomEdges = bottoms
        }

        // Assign lines to cells
        let rowCount = rowBandsSorted.count
        var cellText = Array(
            repeating: Array(repeating: "", count: colCount),
            count: rowCount)

        for line in innerLines {
            let cx = (line.boundingBox.left + line.boundingBox.right) / 2
            let cy = (line.boundingBox.top + line.boundingBox.bottom) / 2
            guard let ci = colBounds.firstIndex(where: { $0.lo <= cx && cx < $0.hi }),
                let ri = (0..<rowCount).first(where: {
                    cy <= rowTopEdges[$0] && cy >= rowBottomEdges[$0]
                })
            else { continue }
            let t = line.text.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                cellText[ri][ci] = cellText[ri][ci].isEmpty ? t : cellText[ri][ci] + " " + t
            }
        }

        // First row with content → headers (re-use original headers to stay stable)
        let dataStart = table.rows.isEmpty ? 1 : 0
        let headers = table.headers  // keep original column names

        let dataRows: [PDFTable.Row] = (dataStart..<rowCount).compactMap { r in
            var cells = [String: String]()
            for c in 0..<colCount where !cellText[r][c].isEmpty {
                cells[headers[c]] = cellText[r][c]
            }
            return cells.isEmpty ? nil : PDFTable.Row(cells: cells)
        }
        guard dataRows.count > table.rows.count else { return table }  // no improvement
        return PDFTable(headers: headers, rows: dataRows)
    }

    // MARK: - Private

    /// Cluster sorted Y values (descending) into row bands using a gap threshold.
    /// Returns one representative Y per band (the mean of the cluster).
    static func clusterY(_ sortedDescY: [Double]) -> [Double] {
        guard !sortedDescY.isEmpty else { return [] }
        var clusters: [[Double]] = [[sortedDescY[0]]]
        for y in sortedDescY.dropFirst() {
            let last = clusters[clusters.count - 1].last!
            if last - y <= rowClusterTolerancePt {
                clusters[clusters.count - 1].append(y)
            } else {
                clusters.append([y])
            }
        }
        return clusters.map { $0.reduce(0, +) / Double($0.count) }
    }
}
