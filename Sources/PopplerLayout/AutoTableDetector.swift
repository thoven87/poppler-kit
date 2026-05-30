import PopplerKit

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

// MARK: - AutoTableDetector
//
// Detects tables from LayoutTextLine arrays using bounding-box clustering.
//
// Algorithm:
//   1. Find candidate "column grid" lines: lines whose text boxes align
//      at ≥ minColumns distinct X positions.
//   2. Group vertically-adjacent grid lines into table regions.
//   3. For each region, build a PDFTable with auto-detected headers
//      (first row) and data rows.
//
// This extends the existing PDFTable keyword approach: no keywords needed,
// and it handles tables anywhere on the page.
public enum AutoTableDetector {
    // MARK: - Configuration
    /// Minimum number of distinct columns to consider a line "tabular".
    public static let minColumns: Int = 2
    /// Minimum number of rows (including header) to emit a table.
    public static let minRows: Int = 2
    /// Maximum vertical gap (pt) between consecutive table rows.
    public static let maxRowGap: Double = 20.0
    /// X-coordinate clustering tolerance (pt).
    public static let xTolerance: Double = 15.0
    /// Minimum column separation as a fraction of page width.
    public static let minColSepRatio: Double = 0.03
    // MARK: - Public
    /// Detect tables in `lines` for a page of the given `pageWidth`.
    /// Returns detected `PDFTable` values and the line-index ranges consumed.
    public static func detect(
        lines: [LayoutTextLine],
        pageWidth: Double
    ) -> [(table: PDFTable, lineRange: Range<Int>)] {
        let minSep = pageWidth * minColSepRatio
        // Step 1: For each line, find the X-cluster centres of its text boxes
        let lineClusters: [[Double]] = lines.map { line in
            clusterXPositions(line.boxes.map(\.boundingBox.left), tolerance: xTolerance)
        }
        // Step 2: Score each line as "tabular" (≥ minColumns well-separated clusters)
        let isTabular: [Bool] = lineClusters.map { clusters in
            guard clusters.count >= minColumns else { return false }
            // Verify minimum separation between consecutive cluster centres
            let sorted = clusters.sorted()
            for i in 1..<sorted.count where sorted[i] - sorted[i - 1] < minSep {
                return false
            }
            return true
        }
        // Step 3: Group consecutive tabular lines into table regions
        var regions: [(start: Int, end: Int)] = []
        var start: Int? = nil
        for (i, tab) in isTabular.enumerated() {
            if tab {
                if start == nil { start = i }
            } else if let s = start {
                // Allow a single non-tabular line gap if the gap is small
                let prevBottom = lines[i - 1].boundingBox.bottom
                let nextTop = i < lines.count ? lines[i].boundingBox.top : 0
                if nextTop - prevBottom <= maxRowGap, i + 1 < lines.count, isTabular[i + 1] {
                    // gap line — keep region open
                } else {
                    if i - s >= minRows { regions.append((s, i)) }
                    start = nil
                }
            }
        }
        if let s = start, lines.count - s >= minRows {
            regions.append((s, lines.count))
        }
        // Step 4: Build PDFTable for each region
        return regions.compactMap { region in
            buildTable(
                lines: lines[region.start..<region.end],
                pageWidth: pageWidth
            )
            .map { ($0, region.start..<region.end) }
        }
    }
    // MARK: - Table construction
    private static func buildTable(lines: ArraySlice<LayoutTextLine>, pageWidth: Double)
        -> PDFTable?
    {
        guard lines.count >= minRows else { return nil }
        let minSep = pageWidth * minColSepRatio
        // Determine column x-boundaries from all lines
        let allLeftX = lines.flatMap { $0.boxes.map(\.boundingBox.left) }
        let colCentres = clusterXPositions(allLeftX, tolerance: xTolerance).sorted()
        guard colCentres.count >= minColumns else { return nil }
        // Validate column separation
        for i in 1..<colCentres.count where colCentres[i] - colCentres[i - 1] < minSep {
            return nil
        }
        // Column boundaries: midpoints between centres
        var colBounds: [(lo: Double, hi: Double)] = []
        for i in 0..<colCentres.count {
            let lo: Double = i == 0 ? -Double.infinity : (colCentres[i - 1] + colCentres[i]) / 2
            let hi: Double =
                i == colCentres.count - 1
                ? Double.infinity : (colCentres[i] + colCentres[i + 1]) / 2
            colBounds.append((lo, hi))
        }
        // Cross-row alignment check: a column must be populated in ≥2 rows to count.
        // This rejects wrapped prose whose word-level boxes happen to form clusters on
        // one line but don't align with boxes on adjacent lines (the lorem-ipsum case).
        var colHitCounts = [Int](repeating: 0, count: colCentres.count)
        for line in lines {
            var rowHits = Set<Int>()
            for box in line.boxes {
                let cx = (box.boundingBox.left + box.boundingBox.right) / 2
                if let ci = colBounds.firstIndex(where: { $0.lo <= cx && cx < $0.hi }) {
                    rowHits.insert(ci)
                }
            }
            for ci in rowHits { colHitCounts[ci] += 1 }
        }
        let alignedColumns = colHitCounts.filter { $0 >= 2 }.count
        // Require that the majority of detected columns are consistently populated
        // across rows. In real tables almost every column appears in every row;
        // in wrapped prose only the left-margin column aligns by coincidence, so
        // the shared fraction is very low (e.g. 2/11 ≈ 18 %).
        guard alignedColumns >= minColumns,
            Double(alignedColumns) / Double(colCentres.count) >= 0.5
        else { return nil }
        // Map each line's boxes to cells
        func cellValues(for line: LayoutTextLine) -> [Int: String] {
            var cells = [Int: [String]]()
            for box in line.boxes {
                let cx = (box.boundingBox.left + box.boundingBox.right) / 2
                if let ci = colBounds.firstIndex(where: { $0.lo <= cx && cx < $0.hi }) {
                    cells[ci, default: []].append(box.text)
                }
            }
            return cells.mapValues { $0.joined(separator: " ") }
        }
        // First row → headers (use startIndex; ArraySlice may not start at 0)
        let headerCells = cellValues(for: lines[lines.startIndex])
        // Deduplicate header names
        var seen = [String: Int]()
        let headers: [String] = colCentres.indices.map { i in
            let name = headerCells[i] ?? "Col\(i + 1)"
            let n = seen[name, default: 0]
            seen[name] = n + 1
            return n == 0 ? name : "\(name) (\(n + 1))"
        }
        // Remaining rows → data
        let dataRows: [PDFTable.Row] = lines.dropFirst().compactMap { line in
            let cells = cellValues(for: line)
            var dict = [String: String]()
            for (i, header) in headers.enumerated() {
                if let v = cells[i], !v.trimmingCharacters(in: .whitespaces).isEmpty {
                    dict[header] = v.trimmingCharacters(in: .whitespaces)
                }
            }
            return dict.isEmpty ? nil : PDFTable.Row(cells: dict)
        }
        guard !dataRows.isEmpty else { return nil }
        return PDFTable(headers: headers, rows: dataRows)
    }
    // MARK: - X-position clustering (greedy single-linkage)
    /// Cluster a list of X coordinates into groups within `tolerance` of each other.
    /// Returns the mean of each cluster (the "column centre").
    static func clusterXPositions(_ xs: [Double], tolerance: Double) -> [Double] {
        guard !xs.isEmpty else { return [] }
        let sorted = xs.sorted()
        var clusters: [[Double]] = [[sorted[0]]]
        for x in sorted.dropFirst() {
            if x - clusters[clusters.count - 1].last! <= tolerance {
                clusters[clusters.count - 1].append(x)
            } else {
                clusters.append([x])
            }
        }
        return clusters.map { $0.reduce(0, +) / Double($0.count) }
    }
}
