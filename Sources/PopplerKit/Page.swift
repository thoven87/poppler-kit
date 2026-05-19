import CPoppler
import CxxStdlib
import Foundation
import Synchronization

/// A Swift wrapper around a single page of a Poppler document.
///
/// ## Concurrency
///
/// `PopplerPage` is safe to share across concurrent `Task`s:
///
/// - **Geometric properties** (`mediaBox`, `cropBox`, `width`, `height`, `orientation`, `label`,
///   `slideDuration`) are lock-free — they read pre-initialised, never-mutated page metadata.
/// - **Text operations** (`text`, `textBoxes`, `text(in:)`, `search`) and `transition()` are
///   protected by an internal `Mutex` — concurrent callers are serialised automatically.
///
/// ```swift
/// // Sharing one page across tasks is safe
/// let page = try doc.page(at: 0)
/// async let t1 = Task { page.text() }           // ← serialised through Mutex
/// async let t2 = Task { page.textBoxes() }       // ← serialised through Mutex
/// ```
public final class PopplerPage: @unchecked Sendable {

    internal let pagePtr: PopplerPagePtr  // set once at init, never mutated

    // Serialises text-extraction and search operations that may trigger
    // poppler's internal TextOutputDev / page cache updates.
    // Geometric reads (page_rect, label, orientation, duration) are lock-free.
    private let _lock = Mutex<Void>(())

    internal init(page: PopplerPagePtr) { self.pagePtr = page }

    deinit { poppler_delete_page(pagePtr) }

    // MARK: - Page Boxes (lock-free — read pre-initialised geometry)

    /// Returns the requested PDF page box in PDF points (1 pt = 1⁄72 inch).
    public func pageRect(_ box: PopplerPageBox = .crop) -> PopplerRect {
        PopplerRect(cRect: poppler_page_get_page_rect(pagePtr, box.rawValue))
    }

    /// Full physical extent of the output medium.
    public var mediaBox: PopplerRect { pageRect(.media) }
    /// Viewer display area (default for `width` and `height`).
    public var cropBox: PopplerRect { pageRect(.crop) }
    /// Print bleed region.
    public var bleedBox: PopplerRect { pageRect(.bleed) }
    /// Final trim size.
    public var trimBox: PopplerRect { pageRect(.trim) }
    /// Artwork extent.
    public var artBox: PopplerRect { pageRect(.art) }

    /// Page width in PDF points (crop box).
    public var width: Double { cropBox.width }
    /// Page height in PDF points (crop box).
    public var height: Double { cropBox.height }

    // MARK: - Page Properties (lock-free)

    /// Physical orientation of the page.
    public var orientation: PopplerPageOrientation {
        PopplerPageOrientation(rawValue: poppler_page_get_orientation(pagePtr)) ?? .portrait
    }

    /// Logical page label (e.g. `"i"`, `"1"`, `"A-1"`), or `nil` if not set.
    public var label: String? { nilIfEmpty(String(poppler_page_get_label(pagePtr))) }

    /// Presentation auto-advance duration in seconds, or `nil` if not set.
    public var slideDuration: Double? {
        let d = poppler_page_get_duration(pagePtr)
        return d >= 0 ? d : nil
    }

    // MARK: - Text Extraction (Mutex-protected)

    /// Extracts the full text content of this page.
    ///
    /// Safe to call concurrently on a shared `PopplerPage` — serialised through
    /// the page's internal `Mutex`.
    public func text(layout: PopplerTextLayout = .natural) -> String {
        _lock.withLock { _ in
            switch layout {
            case .natural:
                return String(poppler_page_text_utf8(pagePtr))
            default:
                return String(poppler_page_text_utf8_with_layout(pagePtr, layout.rawValue))
            }
        }
    }

    /// Extracts the text within a rectangular region.
    ///
    /// Safe to call concurrently on a shared `PopplerPage` — serialised through
    /// the page's internal `Mutex`.
    public func text(in region: PopplerRect, layout: PopplerTextLayout = .natural) -> String {
        _lock.withLock { _ in
            switch layout {
            case .natural:
                return String(
                    poppler_page_text_in_rect(
                        pagePtr, region.left, region.top, region.right, region.bottom))
            default:
                return String(
                    poppler_page_text_in_rect_with_layout(
                        pagePtr, region.left, region.top, region.right, region.bottom,
                        layout.rawValue))
            }
        }
    }

    // MARK: - Text Boxes (Mutex-protected)

    /// Extracts all text boxes with their physical bounding coordinates.
    ///
    /// Safe to call concurrently on a shared `PopplerPage` — serialised through
    /// the page's internal `Mutex`.
    public func textBoxes() -> [PopplerTextBox] {
        _lock.withLock { _ in
            let listPtr = poppler_page_get_text_list(pagePtr)
            defer { poppler_delete_text_list(listPtr) }

            let size = Int(poppler_text_list_get_size(listPtr))
            return (0..<size).map { i in
                let itemPtr = poppler_text_list_get_item(listPtr, Int32(i))
                let text = String(poppler_text_box_get_text_utf8(itemPtr))
                let rect = PopplerRect(cRect: poppler_text_box_get_bbox(itemPtr))
                let fontName: String? =
                    poppler_text_box_has_font_info(itemPtr)
                    ? nilIfEmpty(String(poppler_text_box_get_font_name(itemPtr)))
                    : nil

                let charCount = Int(poppler_text_box_get_text_length(itemPtr))
                let charBBoxes = (0..<charCount).map { j in
                    PopplerRect(cRect: poppler_text_box_get_char_bbox(itemPtr, Int32(j)))
                }

                let wmodeRaw = poppler_text_box_get_wmode(itemPtr, 0)
                let writingMode: PopplerWritingMode =
                    wmodeRaw >= 0
                    ? (PopplerWritingMode(rawValue: wmodeRaw) ?? .horizontal)
                    : .horizontal

                return PopplerTextBox(
                    text: text,
                    boundingBox: rect,
                    fontName: fontName,
                    fontSize: poppler_text_box_get_font_size(itemPtr),
                    rotation: Int(poppler_text_box_get_rotation(itemPtr)),
                    hasSpaceAfter: poppler_text_box_has_space_after(itemPtr),
                    charBBoxes: charBBoxes,
                    writingMode: writingMode
                )
            }
        }
    }

    // MARK: - Search (Mutex-protected)

    /// Finds all occurrences of `text` and returns their bounding boxes.
    ///
    /// Safe to call concurrently on a shared `PopplerPage` — serialised through
    /// the page's internal `Mutex`.
    public func search(for text: String, caseSensitive: Bool = false) -> [PopplerRect] {
        _lock.withLock { _ in
            var results: [PopplerRect] = []
            var left: Double = 0
            var top: Double = 0
            var right: Double = 0
            var bottom: Double = 0
            let cs: Int32 = caseSensitive ? 0 : 1

            var found = text.withCString { ptr in
                poppler_page_search(pagePtr, ptr, &left, &top, &right, &bottom, 0, cs)
            }
            while found {
                results.append(PopplerRect(left: left, top: top, right: right, bottom: bottom))
                found = text.withCString { ptr in
                    poppler_page_search(pagePtr, ptr, &left, &top, &right, &bottom, 1, cs)
                }
            }
            return results
        }
    }

    // MARK: - Presentation (Mutex-protected)

    /// The slide-transition effect applied to this page, or `nil` if none.
    ///
    /// Safe to call concurrently on a shared `PopplerPage` — serialised through
    /// the page's internal `Mutex`.
    public func transition() -> PopplerPageTransition? {
        _lock.withLock { _ in
            guard let ptr = poppler_page_get_transition(pagePtr) else { return nil }
            defer { poppler_delete_page_transition(ptr) }
            return PopplerPageTransition(transitionPtr: ptr)
        }
    }

    // MARK: - Private helpers

    private func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}
