internal import CPopplerBridge

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

public enum PopplerImageFormat: Int, Sendable {
    case invalid = 0
    case mono = 1
    case rgb24 = 2
    case argb32 = 3
    case gray8 = 4
    case bgr24 = 5
}

/// Represents an uncompressed image buffer extracted from a PDF page.
public struct PopplerImage: Sendable {
    /// The width of the image in pixels.
    public let width: Int
    /// The height of the image in pixels.
    public let height: Int
    /// The number of bytes per row.
    public let bytesPerRow: Int
    /// The format of the uncompressed data.
    public let format: PopplerImageFormat
    /// The raw byte data. For RGB24, this will be sequentially stored R, G, B bytes.
    public let data: Data

    internal init(imagePtr: PopplerImagePtr) {
        self.width = Int(poppler_image_get_width(imagePtr))
        self.height = Int(poppler_image_get_height(imagePtr))
        self.bytesPerRow = Int(poppler_image_get_bytes_per_row(imagePtr))
        let formatInt = Int(poppler_image_get_format(imagePtr))
        self.format = PopplerImageFormat(rawValue: formatInt) ?? .invalid

        let rawData = poppler_image_get_data(imagePtr)
        let totalBytes = self.bytesPerRow * self.height

        if totalBytes > 0, let rawData = rawData {
            self.data = Data(bytes: rawData, count: totalBytes)
        } else {
            self.data = Data()
        }
    }
}
