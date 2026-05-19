import Foundation

/// The encoded image format produced when rasterizing PDF pages.
public enum PopplerRasterFormat: String, Sendable {

    /// Lossless PNG. Best quality for OCR, form-data extraction, and archival.
    /// Larger file size than JPEG.
    case png = "png"

    /// Lossy JPEG. Smaller files; well-suited for preview generation and
    /// multimodal LLM inference where slight quality loss is acceptable.
    case jpeg = "jpeg"

    /// File-system extension for this format (same as the raw value).
    var fileExtension: String { rawValue }
}
