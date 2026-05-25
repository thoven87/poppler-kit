internal import CPopplerBridge
import Foundation

/// A rectangle in PDF coordinate space (PDF points; 1 pt = 1⁄72 inch).
///
/// **Coordinate origin:** PDF documents use a bottom-left origin by default — `y = 0` is at
/// the bottom of the page.  This means `top` is numerically *smaller* than `bottom` for
/// content that sits on the page in the normal orientation.  When using coordinates from
/// `PopplerPage.textBoxes()`, normalise against `PopplerPage.mediaBox` to convert to
/// fractional (0…1) space.
public struct PopplerRect: Sendable, Equatable {

    public let left: Double
    public let top: Double
    public let right: Double
    public let bottom: Double

    /// Width of the rectangle (`right − left`).  Non-negative for well-formed rects.
    public var width: Double { right - left }

    /// Height of the rectangle (`bottom − top`).
    /// Positive when `top < bottom`, which is the standard PDF convention.
    public var height: Double { bottom - top }

    /// Creates a `PopplerRect` from explicit coordinates.
    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    internal init(cRect: CPopplerBridge.PopplerRect) {
        self.left = cRect.left
        self.top = cRect.top
        self.right = cRect.right
        self.bottom = cRect.bottom
    }
}
