import Foundation

/// The encoding standard of a font referenced or embedded in a PDF.
/// Maps to `poppler::font_info::type_enum`.
///
/// Useful for PDF/A compliance validation, font auditing, and diagnosing
/// rendering or text-extraction issues caused by unusual font types.
public enum PopplerFontType: Int32, Sendable {
    case unknown = 0
    /// Adobe Type 1 (PostScript outlines).
    case type1 = 1
    /// Type 1 Compact (CFF / Type 1C binary encoding).
    case type1C = 2
    /// Type 1 Compact in an OpenType container (`type1c_ot`).
    case type1COT = 3
    /// Type 3 — procedural glyphs defined as PDF content streams.
    case type3 = 4
    /// TrueType.
    case trueType = 5
    /// TrueType in an OpenType container.
    case trueTypeOT = 6
    /// CID-keyed Type 0 (PostScript, used for CJK).
    case cidType0 = 7
    /// CID-keyed Type 0 Compact (CFF).
    case cidType0C = 8
    /// CID-keyed Type 0 Compact in an OpenType container.
    case cidType0COT = 9
    /// CID-keyed TrueType (`cid_truetype` in poppler).
    case cidTrueType = 10
    /// CID-keyed TrueType in an OpenType container (`cid_truetype_ot` in poppler).
    case cidTrueTypeOT = 11
}
