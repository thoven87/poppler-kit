# Table Extraction

Parse structured tables from PDF pages using coordinate-based column detection.

## How it works

`extractTable(headerKeywords:)` uses ``PopplerPage/textBoxes()`` bounding-box coordinates to:

1. **Group** text boxes into rows by y-coordinate proximity (±5 PDF points by default).
2. **Detect the header zone** — enter on the first row containing a keyword, stay until the first
   row that looks like data.
3. **Cluster** header boxes by x-coordinate to form columns.  Multi-line headers (e.g. `"OFFICE"` /
   `"ACCOUNT"` / `"NUMBER"` stacked across three physical rows) are joined top→bottom per cluster.
4. **Assign data cells** by centre-x to the nearest column boundary.
5. **Filter** rows with fewer than `minimumColumnFill` fraction of columns populated (removes
   footer/totals lines).

The result is a ``PDFTable`` with named ``PDFTable/headers`` and typed ``PDFTable/Row`` data.

## Basic usage

```swift
let page = try doc.page(at: claimsPageIndex)
let table = page.extractTable(
    headerKeywords: ["ACCOUNT", "CHARGED", "ERRORS"]
)

print(table.headers)       // ["OFFICE ACCOUNT NUMBER", "CLIENT NAME", …]
print(table.rows.count)    // number of data rows

for row in table.rows {
    let acct   = row.cell(containing: "ACCOUNT")
    let name   = row.cell(containing: "NAME")
    let amount = row.cell(containing: "CHARGED")
}
```

## Choosing header keywords

Keywords trigger entry into the header zone.  **Avoid words that also appear as cell values**
— they would mis-classify data rows as header rows.

| Avoid (appears in data) | Use instead |
|---|---|
| `"PAID"` (also a status value) | `"CHARGED"` (only in header) |
| `"STATUS"` (also in data) | `"ACCOUNT"` (only in header) |
| `"NAME"` — could be substring of data | OK if data values don't contain "NAME" |

One keyword is enough to trigger header detection; the `startsWithDigit` heuristic terminates it.

## Cell access

### By keyword (recommended)

`cell(containing:)` does a case-insensitive substring search across all column header names:

```swift
let id     = row.cell(containing: "CLIENT ID")    // matches "CLIENT ID."
let status = row.cell(containing: "STATUS")       // exact match
let date   = row.cell(containing: "DATE")         // matches "DATE OF SERVICE"
```

> **Warning:** `"ID"` alone would match both `"CLIENT ID."` and `"PA`**`id`**`"`.
> Use the longest unambiguous fragment.

### By exact header name

```swift
let value = row["OFFICE ACCOUNT NUMBER"]          // exact match, returns nil if absent
```

## Duplicate column headers

When two columns share the same reconstructed header (e.g. two `"DATE OF SERVICE"` columns for
begin and end dates), the second is automatically renamed `"DATE OF SERVICE (2)"`:

```swift
let begin = row.cell(containing: "BEGIN")                    // "BEGIN DATE OF SERVICE"
         ?? row["DATE OF SERVICE"]                            // fallback: first occurrence
let end   = row.cell(containing: "END")                      // "END DATE OF SERVICE"
         ?? row["DATE OF SERVICE (2)"]                        // fallback: second occurrence
         ?? begin                                             // if only one date column
```

## Multi-page tables

Use the `PopplerDocument` overload to accumulate rows from all pages automatically:

```swift
// Claims table spans 7 pages in this remittance PDF
let table = try doc.extractTable(
    headerKeywords: ["ACCOUNT", "CHARGED", "ERRORS"]
)
print(table.rows.count)   // all claims across all pages
```

The column structure is taken from the first qualifying page; subsequent pages are assumed to share
the same layout.

## Tuning parameters

### `xTolerance`

Controls how far apart (in PDF points) two header boxes can be and still belong to the same column.
Pass `nil` (default) to auto-calibrate from `cropBox.width × 0.035` (~21 pt on US letter):

```swift
// Explicit value for very wide or very dense tables
let table = page.extractTable(
    headerKeywords: ["ACCOUNT", "ERRORS"],
    xTolerance: 30.0    // increase if "BEGIN" doesn't cluster with "DATE OF SERVICE"
)
```

### `minimumColumnFill`

Fraction of total columns that must have a value for a row to be included.  Default 0.3 (30%).
Lower it to keep sparse rows; raise it to discard more footer lines:

```swift
let table = page.extractTable(
    headerKeywords: ["ACCOUNT", "ERRORS"],
    minimumColumnFill: 0.2   // keep rows with fewer columns filled
)
```

### `isDataRow`

By default, the header zone ends at the first row whose leftmost box starts with a digit.
Override for tables whose first column starts with text:

```swift
let table = page.extractTable(
    headerKeywords: ["SKU", "DESCRIPTION"],
    isDataRow: { row in
        // A data row starts with a SKU like "AB-1234"
        row.first?.text.contains("-") == true
    }
)
```

## Validating parsed data

If your table has a corresponding summary section in the same PDF (like totals on a remittance),
verify the extracted data against it:

```swift
let remittance = try await RemittanceParser().parse(from: url)
let issues = remittance.validate()

guard issues.isEmpty else {
    issues.forEach { print("WARNING: \($0)") }
    throw ParserError.validationFailed
}
```
