#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

// MARK: - PDFTable

/// A structured table extracted from a PDF page via bounding-box coordinate analysis.
///
/// Obtain an instance through `PopplerPage.extractTable(headerKeywords:)`.
/// Access cells by keyword rather than exact header name to stay robust against
/// multi-line headers that poppler reconstructs slightly differently across PDF versions:
///
/// ```swift
/// let table = page.extractTable(headerKeywords: ["TCN", "CHARGED", "PAID", "STATUS"])
/// for row in table.rows {
///     let tcn     = row.cell(containing: "TCN")
///     let charged = row.cell(containing: "CHARGED")
///     let status  = row.cell(containing: "STATUS")
/// }
/// ```
public struct PDFTable: Sendable {

    // MARK: - Row

    /// One data row of the table.
    public struct Row: Sendable {

        /// All non-empty cells, keyed by the full reconstructed column-header string.
        public let cells: [String: String]

        public init(cells: [String: String]) {
            self.cells = cells
        }

        /// Returns the cell under the column whose header is **exactly** `header`.
        public subscript(header: String) -> String? {
            guard let v = cells[header], !v.isEmpty else { return nil }
            return v
        }

        /// Returns the first non-empty cell whose column header **contains** `keyword`
        /// (case-insensitive search).
        ///
        /// This is the preferred access method when the exact multi-line header text
        /// is not known in advance, e.g. `row.cell(containing: "TCN")` matches a
        /// header reconstructed as either `"TCN"` or `"TCN ID"`.
        public func cell(containing keyword: String) -> String? {
            // Pre-lowercase once; avoids a redundant allocation on every key check.
            let lowerKeyword = keyword.lowercased()
            return cells.first {
                !$0.value.isEmpty && $0.key.lowercased().contains(lowerKeyword)
            }?.value
        }
    }

    // MARK: - Table

    public init(headers: [String], rows: [Row]) {
        self.headers = headers
        self.rows = rows
    }

    /// Ordered column headers (left → right).
    ///
    /// Multi-line headers are joined top → bottom with spaces:
    /// e.g. three stacked boxes `"OFFICE"` / `"ACCOUNT"` / `"NUMBER"` become
    /// `"OFFICE ACCOUNT NUMBER"`.
    public let headers: [String]

    /// Data rows only (header rows and footer/total rows are excluded).
    public let rows: [Row]

    /// All non-empty values for the column whose header exactly matches `header`.
    public func column(_ header: String) -> [String] {
        rows.compactMap { $0[header] }
    }

    /// All non-empty values for the first column whose header contains `keyword`.
    public func column(containing keyword: String) -> [String] {
        rows.compactMap { $0.cell(containing: keyword) }
    }

    /// `true` when no data rows were extracted.
    public var isEmpty: Bool { rows.isEmpty }
}

// MARK: - PopplerPage extension

extension PopplerPage {

    /// Extracts a structured table from this page using bounding-box coordinate analysis.
    ///
    /// ## Algorithm
    ///
    /// 1. **Sort** all `PopplerTextBox` objects top → bottom, then left → right.
    /// 2. **Group into rows** by `yTolerance` (boxes within ±5 PDF pt vertically share a row).
    /// 3. **Identify the header zone** — consecutive rows whose text contains at least one word
    ///    from `headerKeywords`.  Rows that appear before any keyword row (e.g. page-level
    ///    provider metadata) are silently skipped.
    /// 4. **Cluster header boxes** by x-coordinate proximity within `xTolerance` to build
    ///    column definitions.  Boxes at the same x across multiple physical header lines
    ///    are joined top → bottom to produce the full column-header string.
    /// 5. **Compute column x-boundaries** as midpoints between adjacent cluster centres.
    /// 6. **Map data rows** by assigning each cell to the column whose x-range contains the
    ///    cell's horizontal centre.  Rows that populate fewer than `minimumColumnFill`
    ///    of total columns are discarded (removes totals/footer lines).
    ///
    /// ## Parameters
    ///
    /// - `headerKeywords`: Uppercase words that appear in column-header rows.
    ///   Example: `["ACCOUNT", "TCN", "CHARGED", "STATUS"]`.
    /// - `yTolerance`: Maximum vertical distance (PDF pts) between two boxes in the same row.
    ///   Default `5`. Increase for documents with larger leading.
    /// - `xTolerance`: Maximum horizontal distance for two header boxes to belong to the same
    ///   column.  Default `20`. Increase if header words in the same column spread further apart.
    /// - `xTolerance`: Maximum x-delta for two header boxes in the same column.
    ///   Pass `nil` (default) to auto-calibrate from `cropBox.width × 0.035`.
    /// - `minimumColumnFill`: Minimum fraction of columns with a value for a data row to be
    ///   included.  Default 0.3 filters out sparse footer / totals lines.
    /// - `isDataRow`: Closure that returns `true` when a row should exit the header zone.
    ///   Default: the leftmost non-empty box begins with a digit.  Override for tables
    ///   whose first data column starts with text.
    public func extractTable(
        headerKeywords: Set<String>,
        yTolerance: Double = 5.0,
        xTolerance: Double? = nil,
        minimumColumnFill: Double = 0.3,
        isDataRow: (@Sendable ([PopplerTextBox]) -> Bool)? = nil
    ) -> PDFTable {
        let allBoxes = textBoxes()
        guard !allBoxes.isEmpty else { return PDFTable(headers: [], rows: []) }

        // Auto-calibrate xTolerance from crop-box width when not specified.
        // ~3.5% of page width scales naturally with column density:
        // 612 pt letter × 0.035 = 21.4 pt  (13 columns, ~47 pt each)
        // 420 pt A5     × 0.035 = 14.7 pt  (narrower, tighter columns)
        let effectiveXTol = xTolerance ?? (cropBox.width * 0.035)

        // Resolved data-row detector: caller’s closure, or the default digit-first heuristic.
        let checkIsDataRow: ([PopplerTextBox]) -> Bool =
            isDataRow ?? { row in
                let leftmost =
                    row
                    .sorted { $0.boundingBox.left < $1.boundingBox.left }
                    .first { !$0.text.trimmingWhitespace().isEmpty }
                return leftmost?.text.trimmingWhitespace().first?.isNumber == true
            }

        // 1. Sort top → bottom, left → right
        let sorted = allBoxes.sorted {
            let dy = $0.boundingBox.top - $1.boundingBox.top
            if abs(dy) > yTolerance { return dy < 0 }
            return $0.boundingBox.left < $1.boundingBox.left
        }

        // 2. Group into rows
        var rawRows: [[PopplerTextBox]] = []
        for box in sorted {
            if let last = rawRows.last,
                let anchor = last.first,
                abs(box.boundingBox.top - anchor.boundingBox.top) <= yTolerance
            {
                rawRows[rawRows.count - 1].append(box)
            } else {
                rawRows.append([box])
            }
        }

        // 3. Partition: header zone vs data rows.
        //
        // Two-phase approach that handles multi-line headers correctly:
        //
        // Phase A — Pre-header: rows before the table are page-level metadata
        //   (provider name, dates, etc.).  We skip them until a keyword row fires.
        //
        // Phase B — Header zone: we enter this zone on the first keyword match and
        //   stay in it even for rows that have NO keyword (mid-levels of a multi-line
        //   header like "OFFICE / ACCOUNT / NUMBER" across three physical rows).
        //   The zone ends when the leftmost non-empty box of a row begins with a digit
        //   — that signals the first data row.
        //
        // Phase C — Data zone: all subsequent rows are data rows.
        //   Footer / totals rows (few columns) are filtered later by minimumColumnFill.
        //
        // NOTE: keywords must be chosen so they appear in header rows but NOT in data
        // cells.  Avoid status words like "PAID" or "DENY" which appear as cell values.
        var headerRows: [[PopplerTextBox]] = []
        var dataRows: [[PopplerTextBox]] = []
        var inHeaderZone = false
        var pastHeaders = false

        for row in rawRows {
            let words = row.map { $0.text.uppercased() }
            let hasKeyword = headerKeywords.contains { kw in
                words.contains { $0.contains(kw) }
            }

            if !inHeaderZone && !pastHeaders {
                if hasKeyword {
                    inHeaderZone = true  // enter header zone
                    headerRows.append(row)
                }
                // else: pre-table metadata — skip silently

            } else if inHeaderZone {
                if checkIsDataRow(row) {
                    // First data row ends the header zone
                    inHeaderZone = false
                    pastHeaders = true
                    dataRows.append(row)
                } else {
                    // Continuation of multi-line header
                    headerRows.append(row)
                }

            } else if pastHeaders {
                dataRows.append(row)
            }
        }
        guard !headerRows.isEmpty else { return PDFTable(headers: [], rows: []) }

        // 4. Cluster header boxes by x-proximity
        let headerBoxes = headerRows.flatMap { $0 }
            .sorted { $0.boundingBox.left < $1.boundingBox.left }
        var clusters: [[PopplerTextBox]] = []

        for box in headerBoxes {
            let bx = box.boundingBox.left
            if let idx = clusters.indices.first(where: { i in
                let avg =
                    clusters[i].map { $0.boundingBox.left }.reduce(0.0, +)
                    / Double(clusters[i].count)
                return abs(bx - avg) <= effectiveXTol
            }) {
                clusters[idx].append(box)
            } else {
                clusters.append([box])
            }
        }

        // Sort clusters left → right by mean x
        func meanX(_ c: [PopplerTextBox]) -> Double {
            c.map { $0.boundingBox.left }.reduce(0.0, +) / Double(c.count)
        }
        clusters.sort { meanX($0) < meanX($1) }

        // Build (header, centre-x) per column
        let cols: [(name: String, cx: Double)] = clusters.map { cluster in
            let name =
                cluster
                .sorted { $0.boundingBox.top < $1.boundingBox.top }
                .map { $0.text.trimmingWhitespace() }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let cx =
                cluster
                .map { $0.boundingBox.left + $0.boundingBox.width / 2 }
                .reduce(0.0, +) / Double(cluster.count)
            return (name, cx)
        }
        // Deduplicate same-name column headers by appending a count suffix.
        // This preserves both cells when adjacent columns share the same multi-line
        // header text (e.g. two "DATE OF SERVICE" columns for begin and end dates).
        var seenNames: [String: Int] = [:]
        let headers: [String] = cols.map { col in
            let n = col.name
            let idx = seenNames[n, default: 0]
            seenNames[n] = idx + 1
            return idx == 0 ? n : "\(n) (\(idx + 1))"
        }

        // 5. Column x-boundaries: midpoints between adjacent centres
        let bounds: [(lo: Double, hi: Double)] = cols.indices.map { i in
            let lo: Double =
                i == 0
                ? -.infinity
                : (cols[i - 1].cx + cols[i].cx) / 2
            let hi: Double =
                i == cols.endIndex - 1
                ? .infinity
                : (cols[i].cx + cols[i + 1].cx) / 2
            return (lo, hi)
        }
        let minCells = max(1, Int((minimumColumnFill * Double(headers.count)).rounded()))

        // 6. Map data rows to cell dictionaries
        let tableRows: [PDFTable.Row] = dataRows.compactMap { row in
            var colTexts: [Int: [String]] = [:]

            for box in row {
                let cx = box.boundingBox.left + box.boundingBox.width / 2
                if let ci = bounds.firstIndex(where: { $0.lo <= cx && cx < $0.hi }) {
                    colTexts[ci, default: []].append(box.text)
                }
            }

            guard colTexts.count >= minCells else { return nil }

            var cells: [String: String] = [:]
            for (ci, texts) in colTexts where ci < headers.count {
                let v = texts.joined(separator: " ").trimmingWhitespace()
                if !v.isEmpty { cells[headers[ci]] = v }
            }
            return cells.isEmpty ? nil : PDFTable.Row(cells: cells)
        }

        return PDFTable(headers: headers, rows: tableRows)
    }
}

// MARK: - PopplerDocument: multi-page table extraction

extension PopplerDocument {

    /// Extracts a table that spans **multiple pages** of a document.
    ///
    /// Iterates every page; pages that contain the header-keyword columns have
    /// their data rows accumulated into a single `PDFTable`.  The column headers
    /// are taken from the **first qualifying page**; subsequent pages are expected
    /// to share the same column structure (typical for paginated reports).
    ///
    /// ```swift
    /// // Extract the claims table across all pages of a remittance PDF
    /// let table = try doc.extractTable(
    ///     headerKeywords: ["ACCOUNT", "CHARGED", "ERRORS"]
    /// )
    /// print(table.rows.count) // all claims across all pages
    /// ```
    ///
    /// - Parameters: same as `PopplerPage.extractTable(headerKeywords:...)`.
    public func extractTable(
        headerKeywords: Set<String>,
        yTolerance: Double = 5.0,
        xTolerance: Double? = nil,
        minimumColumnFill: Double = 0.3,
        isDataRow: (@Sendable ([PopplerTextBox]) -> Bool)? = nil
    ) throws -> PDFTable {
        var baseHeaders: [String]? = nil
        var allRows: [PDFTable.Row] = []

        for i in 0..<pageCount {
            let pg = try page(at: i)
            let table = pg.extractTable(
                headerKeywords: headerKeywords,
                yTolerance: yTolerance,
                xTolerance: xTolerance,
                minimumColumnFill: minimumColumnFill,
                isDataRow: isDataRow
            )
            guard !table.isEmpty else { continue }
            if baseHeaders == nil { baseHeaders = table.headers }
            allRows.append(contentsOf: table.rows)
        }

        guard let headers = baseHeaders else {
            return PDFTable(headers: [], rows: [])
        }
        return PDFTable(headers: headers, rows: allRows)
    }
}
