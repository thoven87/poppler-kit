import CPoppler
import Foundation

/// Metadata about a single font referenced or embedded in a PDF document.
public struct PopplerFontInfo: Sendable {

    /// The PostScript or OpenType name of the font.
    public let name: String

    /// File-system path to the font file, if available on the host system.
    public let file: String

    /// The encoding/format standard of this font.
    public let type: PopplerFontType

    /// `true` if the full font program is embedded in the PDF.
    public let isEmbedded: Bool

    /// `true` if only the subset of glyphs actually used in the document is embedded.
    ///
    /// Subset fonts cannot be used to render glyphs outside the document's own text,
    /// which matters for PDF repair, accessibility tooling, and PDF/A validation.
    public let isSubset: Bool

    internal init(fontPtr: PopplerFontInfoPtr) {
        self.name = String(poppler_font_info_get_name(fontPtr))
        self.file = String(poppler_font_info_get_file(fontPtr))
        self.type = PopplerFontType(rawValue: poppler_font_info_get_type(fontPtr)) ?? .unknown
        self.isEmbedded = poppler_font_info_is_embedded(fontPtr)
        self.isSubset = poppler_font_info_is_subset(fontPtr)
    }
}
