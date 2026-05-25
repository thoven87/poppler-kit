internal import CPopplerBridge
import Foundation

/// A distinct run of text on a page, with physical bounding coordinates.
///
/// Roughly corresponds to one word or glyph group.  Use `boundingBox`
/// together with `PopplerPage.mediaBox` to normalise coordinates:
/// ```swift
/// let normX = box.boundingBox.left / page.width
/// ```
public struct PopplerTextBox: Sendable, Equatable {

    /// The text content of this box (one word or glyph run).
    public let text: String

    /// Bounding box in PDF points (same coordinate system as `PopplerPage.mediaBox`).
    public let boundingBox: PopplerRect

    /// Font name used for this text run, or `nil` if not available.
    public let fontName: String?

    /// Font size in PDF points.
    public let fontSize: Double

    /// Rotation of the text box: 0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°.
    public let rotation: Int

    /// `true` if a space character immediately follows this text box.
    public let hasSpaceAfter: Bool

    /// Per-glyph bounding boxes in PDF points, aligned with the UCS4 code points of `text`.
    ///
    /// May be shorter than `text.unicodeScalars.count` for complex scripts (ligatures,
    /// combining marks).  Returns `PopplerRect(0,0,0,0)` for out-of-range indices.
    ///
    /// Use these alongside `boundingBox` when you need character-level hit-testing or
    /// highlighting.
    public let charBBoxes: [PopplerRect]

    /// Writing direction of the glyphs in this box.
    ///
    /// `.horizontal` for Latin, Cyrillic, Arabic, Hebrew, etc.;
    /// `.vertical` for CJK vertical text.
    public let writingMode: PopplerWritingMode

    internal init(
        text: String,
        boundingBox: PopplerRect,
        fontName: String?,
        fontSize: Double,
        rotation: Int,
        hasSpaceAfter: Bool,
        charBBoxes: [PopplerRect],
        writingMode: PopplerWritingMode
    ) {
        self.text = text
        self.boundingBox = boundingBox
        self.fontName = fontName
        self.fontSize = fontSize
        self.rotation = rotation
        self.hasSpaceAfter = hasSpaceAfter
        self.charBBoxes = charBBoxes
        self.writingMode = writingMode
    }
}
