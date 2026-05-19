import Foundation

/// Controls the text-extraction algorithm applied when reading a page's text content.
///
/// Equivalent `pdftotext` flags for reference:
/// - `.physical`  → `-layout`   (preserve columns and rows)
/// - `.rawOrder`  → `-raw`      (content-stream order)
/// - `.natural`   → *(default)* (logical reading order)
public enum PopplerTextLayout: Int32, Sendable {

    /// Reconstructs the physical placement of text, preserving columns and rows.
    /// Best for multi-column documents, tables, and structured forms.
    /// Corresponds to `poppler::page::physical_layout` (available since poppler 0.16).
    case physical = 0

    /// Follows the raw PDF content-stream order, ignoring visual positioning.
    /// Fastest extraction; may produce out-of-reading-order output for complex layouts.
    /// Corresponds to `poppler::page::raw_order_layout` (available since poppler 0.16).
    case rawOrder = 1

    /// Logical reading order without strict physical placement constraints.
    /// A good default for prose and mixed-layout documents.
    /// Corresponds to `poppler::page::non_raw_non_physical_layout` (requires poppler ≥ 0.88).
    case natural = 2
}
