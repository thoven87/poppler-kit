import Foundation

/// The physical orientation of a PDF page.
/// Maps to `poppler::page::orientation_enum`.
///
/// Orientation affects how `mediaBox` coordinates map to screen space.
/// A renderer must account for orientation to produce correctly-rotated output.
public enum PopplerPageOrientation: Int32, Sendable {
    /// 90° clockwise from portrait (wide side at top).
    case landscape = 0
    /// Standard upright orientation (tall side at top).
    case portrait = 1
    /// 90° counter-clockwise from portrait.
    case seascape = 2
    /// 180° from portrait (upside-down).
    case upsideDown = 3
}
