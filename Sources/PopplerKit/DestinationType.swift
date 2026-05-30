/// The type of a named PDF destination, which determines which coordinate fields
/// on `PopplerDestination` are meaningful.
/// Maps to `poppler::destination::type_enum`.
public enum PopplerDestinationType: Int32, Sendable {
    /// Unknown or unsupported destination type.
    case unknown = 0

    /// Explicit position: `left`, `top`, and `zoom` are all meaningful.
    case xyz = 1

    /// Fit the entire page into the viewer window. No coordinates are meaningful.
    case fit = 2

    /// Fit the full page width. `top` specifies the vertical scroll position.
    case fitH = 3

    /// Fit the full page height. `left` specifies the horizontal scroll position.
    case fitV = 4

    /// Fit the page's content bounding box into the viewer. No coordinates meaningful.
    case fitB = 5

    /// Fit the bounding-box width. `top` specifies the vertical position.
    case fitBH = 6

    /// Fit the bounding-box height. `left` specifies the horizontal position.
    case fitBV = 7

    /// Fit the rectangle defined by `left`, `top`, `right`, and `bottom`.
    case fitR = 8
}
