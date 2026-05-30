internal import CPopplerBridge

/// A named destination (bookmark or cross-link target) within a PDF document.
public struct PopplerDestination: Sendable {

    /// The name of this destination (used in links and the TOC).
    public let name: String

    /// The destination type, which determines which coordinate fields are meaningful.
    ///
    /// Only read `left`, `top`, and `zoom` for `.xyz`; only `left`/`top` for `.fitH`/`.fitV`/
    /// `.fitBH`/`.fitBV`; all four sides for `.fitR`; none for `.fit`/`.fitB`.
    public let type: PopplerDestinationType

    /// The 1-based page number this destination points to.
    public let pageNumber: Int

    /// Left X coordinate in PDF points. Meaningful for `.xyz`, `.fitV`, `.fitBV`, `.fitR`.
    public let left: Double

    /// Top Y coordinate in PDF points. Meaningful for `.xyz`, `.fitH`, `.fitBH`, `.fitR`.
    public let top: Double

    /// Zoom level. Meaningful only for `.xyz` (0 means "keep current zoom").
    public let zoom: Double

    internal init(name: String, destPtr: PopplerDestinationPtr) {
        self.name = name
        self.type =
            PopplerDestinationType(rawValue: poppler_destination_get_type(destPtr)) ?? .unknown
        self.pageNumber = Int(poppler_destination_get_page_number(destPtr))
        self.left = poppler_destination_get_left(destPtr)
        self.top = poppler_destination_get_top(destPtr)
        self.zoom = poppler_destination_get_zoom(destPtr)
    }
}
