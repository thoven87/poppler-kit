#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import PopplerKit

// MARK: - LayoutTextLine

/// A visual line of text composed of one or more `PopplerTextBox` items
/// that share the same baseline.
public struct LayoutTextLine: Sendable {
    public let boxes: [PopplerTextBox]
    public let boundingBox: PopplerRect
    public let fontSize: Double
    public let fontName: String?

    /// Full text of the line, boxes joined left→right with a single space.
    public var text: String {
        boxes.map(\.text).joined(separator: " ")
    }

    init(boxes: [PopplerTextBox]) {
        precondition(!boxes.isEmpty)
        self.boxes = boxes
        self.fontSize = boxes.map(\.fontSize).max() ?? 0
        self.fontName = boxes.first?.fontName
        let left = boxes.map(\.boundingBox.left).min()!
        let right = boxes.map(\.boundingBox.right).max()!
        let top = boxes.map(\.boundingBox.top).max()!
        let bottom = boxes.map(\.boundingBox.bottom).min()!
        self.boundingBox = PopplerRect(left: left, top: top, right: right, bottom: bottom)
    }
}

// MARK: - PopplerLayoutElement

/// A semantically-typed element extracted from a PDF page or document.
public enum PopplerLayoutElement: Sendable {

    /// A heading with a hierarchy level (1 = largest, 6 = smallest).
    case heading(level: Int, text: String, boundingBox: PopplerRect, fontSize: Double)

    /// A body paragraph.
    case paragraph(text: String, boundingBox: PopplerRect)

    /// A single list item.
    ///
    /// - `label`: The bullet / number prefix (e.g. `"1."`, `"•"`), or `nil` for unlabelled items.
    /// - `nestingLevel`: Indentation depth starting at 1.  Top-level items are `1`;
    ///   once-indented items are `2`, etc.  Determined by comparing the item's left-edge
    ///   X position against the page's dominant body-text margin.
    case listItem(label: String?, text: String, boundingBox: PopplerRect, nestingLevel: Int)

    /// A figure or table caption detected by the `"Fig."` / `"Table"` prefix pattern.
    case caption(text: String, boundingBox: PopplerRect)

    /// A detected table.
    case table(PDFTable, boundingBox: PopplerRect)

    /// A page header (repeating content at the top of multiple pages).
    case header(text: String, boundingBox: PopplerRect)

    /// A page footer (repeating content at the bottom of multiple pages).
    case footer(text: String, boundingBox: PopplerRect)

    // MARK: Convenience accessors

    public var boundingBox: PopplerRect {
        switch self {
        case .heading(_, _, let r, _): return r
        case .paragraph(_, let r): return r
        case .listItem(_, _, let r, _): return r
        case .caption(_, let r): return r
        case .table(_, let r): return r
        case .header(_, let r): return r
        case .footer(_, let r): return r
        }
    }

    /// Plain text content regardless of element type.
    public var text: String {
        switch self {
        case .heading(_, let t, _, _): return t
        case .paragraph(let t, _): return t
        case .listItem(let lbl, let t, _, _):
            if let lbl { return "\(lbl) \(t)" } else { return t }
        case .caption(let t, _): return t
        case .table(let tbl, _):
            return tbl.rows.map { row in
                row.cells.values.joined(separator: "\t")
            }.joined(separator: "\n")
        case .header(let t, _): return t
        case .footer(let t, _): return t
        }
    }

    /// `true` for `.header` and `.footer` — repeating chrome that callers typically strip.
    public var isChrome: Bool {
        if case .header = self { return true }
        if case .footer = self { return true }
        return false
    }
}

// MARK: - CaptionDetector (internal)

/// Identifies figure / table caption lines by their standard prefix pattern.
///
/// Matches (case-insensitive):  "Fig. 1", "Figure 2:", "Table I", "TABLE II.",
/// "Chart 3", "Algorithm 1", "Listing 2", "Appendix A", etc.
enum CaptionDetector {

    // Matches figure / table caption prefixes (case-insensitive) followed by a
    // number or roman-numeral marker: "Fig. 1", "Figure 2:", "TABLE I.", etc.
    nonisolated(unsafe) private static let captionRegex =
        #/(?i)^(?:fig(?:ure)?|table|chart|photo|image|plate|diagram|scheme|algorithm|listing|exhibit|appendix|supplementary)\s*[.:\s]\s*[\dIVXivxA-Fa-f]/#

    static func isCaption(_ line: LayoutTextLine) -> Bool {
        let t = line.text.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.firstMatch(of: captionRegex) != nil
    }
}
