import Foundation

/// The direction glyphs are laid out within a `PopplerTextBox`.
/// Maps to `poppler::text_box::writing_mode_enum`.
public enum PopplerWritingMode: Int32, Sendable {
    /// Left-to-right or right-to-left horizontal layout.
    /// Used by Latin, Cyrillic, Arabic, Hebrew, and most other scripts.
    case horizontal = 0
    /// Top-to-bottom vertical layout.
    /// Used by CJK (Chinese, Japanese, Korean) vertical writing mode.
    case vertical = 1
}
