internal import CPopplerBridge
import Foundation

/// A file attachment embedded within a PDF document.
public struct PopplerEmbeddedFile: Sendable {

    /// The filename of the attachment.
    public let name: String

    /// MIME type of the file (e.g. `"application/pdf"`, `"image/png"`).
    public let mimeType: String

    /// Optional human-readable description provided by the document author.
    public let fileDescription: String?

    /// Declared file size in bytes (may differ from `data.count` if the PDF is malformed).
    public let size: Int

    /// Lowercase hex-encoded checksum of the file data, or `nil` if not embedded in the PDF.
    ///
    /// Use this to verify the integrity of `data` after extraction.
    public let checksum: String?

    /// The date the attachment was originally created, or `nil` if not recorded.
    public let creationDate: Date?

    /// The date the attachment was last modified, or `nil` if not recorded.
    public let modificationDate: Date?

    /// The raw byte content of the attachment.
    public let data: Data

    /// Returns `nil` if the embedded file entry is invalid or corrupt.
    internal init?(filePtr: PopplerEmbeddedFilePtr) {
        guard poppler_embedded_file_is_valid(filePtr) else { return nil }

        self.name = String(cString: poppler_embedded_file_get_name(filePtr))
        self.mimeType = String(cString: poppler_embedded_file_get_mime_type(filePtr))
        self.size = Int(poppler_embedded_file_get_size(filePtr))

        let desc = String(cString: poppler_embedded_file_get_description(filePtr))
        self.fileDescription = desc.isEmpty ? nil : desc

        let hex = String(cString: poppler_embedded_file_get_checksum(filePtr))
        self.checksum = hex.isEmpty ? nil : hex

        let cDate = poppler_embedded_file_get_creation_date(filePtr)
        self.creationDate = cDate != -1 ? Date(timeIntervalSince1970: TimeInterval(cDate)) : nil

        let mDate = poppler_embedded_file_get_modification_date(filePtr)
        self.modificationDate = mDate != -1 ? Date(timeIntervalSince1970: TimeInterval(mDate)) : nil

        let arrPtr = poppler_embedded_file_get_data(filePtr)
        defer { poppler_delete_byte_array(arrPtr) }
        let rawPtr = poppler_byte_array_get_data(arrPtr)
        let rawSize = Int(poppler_byte_array_get_size(arrPtr))
        if rawSize > 0, let rawPtr {
            self.data = Data(bytes: rawPtr, count: rawSize)
        } else {
            self.data = Data()
        }
    }
}
