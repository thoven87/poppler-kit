internal import CPopplerBridge

/// A line segment extracted from the PDF page's vector graphics content.
///
/// Segments come from PDF path-painting operators (`S` = stroke, `f`/`B` = fill)
/// and represent the actual drawn lines in the document — table borders, dividers,
/// underlines, and other decorative elements.
///
/// Coordinates are in PDF page space (origin bottom-left, y increases upward),
/// the same system used by `PopplerRect` and `PopplerTextBox.boundingBox`.
public struct PopplerLineArtSegment: Sendable, Equatable {
    /// Start point x in PDF points.
    public let x1: Double
    /// Start point y in PDF points (distance from page bottom).
    public let y1: Double
    /// End point x in PDF points.
    public let x2: Double
    /// End point y in PDF points.
    public let y2: Double
    /// Red component of the drawn color, 0.0–1.0.
    public let r: Double
    /// Green component of the drawn color, 0.0–1.0.
    public let g: Double
    /// Blue component of the drawn color, 0.0–1.0.
    public let b: Double
    /// Stroke width in PDF points; 0 for filled (area) segments.
    public let lineWidth: Double

    // MARK: - Derived geometry

    /// Horizontal extent of the segment in PDF points.
    public var width: Double { abs(x2 - x1) }
    /// Vertical extent of the segment in PDF points.
    public var height: Double { abs(y2 - y1) }
    /// Length of the segment in PDF points.
    public var length: Double { (width * width + height * height).squareRoot() }

    /// `true` when the segment is within `angleTolerance` degrees of horizontal.
    public func isHorizontal(angleTolerance: Double = 3.0) -> Bool {
        guard length > 0 else { return false }
        // height/length == sin(θ) where θ is the angle from horizontal.
        // For angles below ~10° the small-angle approximation sin(θ) ≈ θ
        // is accurate to < 0.5 %, avoiding a platform-specific math import.
        return height / length < angleTolerance * (.pi / 180)
    }

    /// `true` when the segment is within `angleTolerance` degrees of vertical.
    public func isVertical(angleTolerance: Double = 3.0) -> Bool {
        guard length > 0 else { return false }
        return width / length < angleTolerance * (.pi / 180)
    }

    /// Axis-aligned bounding box of the segment.
    public var boundingBox: PopplerRect {
        PopplerRect(
            left: min(x1, x2),
            top: max(y1, y2),
            right: max(x1, x2),
            bottom: min(y1, y2)
        )
    }
}
