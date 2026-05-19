import Foundation

/// One of the five PDF page box regions.
///
/// Each box is a rectangle in PDF points (1 pt = 1⁄72 inch) that defines
/// a different boundary of the page. The boxes form a conceptual hierarchy:
/// `media ⊇ bleed ⊇ trim` for print workflows, and `crop` is the viewer's display area.
///
/// Maps to `poppler::page_box_enum`.
public enum PopplerPageBox: Int32, Sendable {
    /// The full physical extent of the output medium — the largest box.
    /// All other boxes must fit within or equal the media box.
    case media = 0

    /// The region the viewer displays and prints.
    /// Defaults to `media` if the PDF does not define a crop box.
    /// This is the box most applications use for layout and rendering.
    case crop = 1

    /// The bleed region for offset printing, extending slightly beyond `trim`
    /// to account for ink bleed during the trimming process.
    case bleed = 2

    /// The final intended size of the physical page after trimming.
    case trim = 3

    /// The extent of meaningful artwork as defined by the document creator.
    case art = 4
}
