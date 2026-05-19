import Foundation

/// Errors that can occur when interacting with PopplerKit.
public enum PopplerError: Error, CustomStringConvertible {

    /// The document could not be opened — the file may be missing, corrupt, or unsupported.
    /// If the PDF is password-protected, retry with `ownerPassword` / `userPassword`.
    case documentLoadFailed

    /// The document is locked and requires a password that was not supplied or is incorrect.
    case passwordRequired

    /// A page index is out of bounds for the document's `pageCount`.
    case invalidPage

    /// A page range is invalid (e.g. `firstPage > lastPage`, or either bound is out of range).
    case invalidPageRange

    /// Rendering a page to a raster image failed — the rendered image is invalid.
    case renderingFailed

    /// Encoding a rendered image to the requested format failed.
    case encodingFailed

    /// Writing the document to disk failed.
    case saveFailed

    public var description: String {
        switch self {
        case .documentLoadFailed:
            return
                "Failed to open the PDF — check the file path, integrity, and any required password."
        case .passwordRequired:
            return "The document is locked; supply the correct owner or user password."
        case .invalidPage:
            return "Page index is out of bounds."
        case .invalidPageRange:
            return "Page range is invalid or out of bounds."
        case .renderingFailed:
            return "Page rendering failed — the output image is invalid."
        case .encodingFailed:
            return "Failed to encode the rendered image to the requested format."
        case .saveFailed:
            return "Failed to write the document to the specified path."
        }
    }
}
