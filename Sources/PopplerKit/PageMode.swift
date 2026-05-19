import Foundation

/// How PDF pages should be laid out when the document is opened in a viewer.
/// Maps to `poppler::document::page_layout_enum`.
public enum PopplerPageLayout: Int32, Sendable {
    case none = 0
    case singlePage = 1
    case oneColumn = 2
    case twoColumnLeft = 3
    case twoColumnRight = 4
    case twoPageLeft = 5
    case twoPageRight = 6
}

/// How the viewer's UI chrome should appear when the document is first opened.
/// Maps to `poppler::document::page_mode_enum`.
public enum PopplerPageMode: Int32, Sendable {
    case none = 0
    case useOutlines = 1
    case useThumbs = 2
    case fullScreen = 3
    case useOptionalContent = 4
    case useAttachments = 5
}
