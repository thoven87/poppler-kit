internal import CPopplerBridge
import Synchronization

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// Renders PDF pages to raster image buffers or encoded image files.
///
/// The renderer pointer is stored **inside** a `Mutex<PopplerRendererPtr>` — the
/// compiler structurally prevents accessing it outside `withLock`.  This makes
/// a single `PopplerRenderer` instance safe to share across concurrent `Task`s;
/// rendering calls from different tasks are serialised through the lock.
///
/// **Shared renderer** — safe, rendering is serialised:
///
/// ```swift
/// let renderer = PopplerRenderer()
/// renderer.setAntialiasing(true)
///
/// let images = try await doc.withConcurrentPages { page, _ in
///     renderer.renderToData(page: page, xres: 150)  // serialised through Mutex
/// }
/// ```
///
/// **Per-task renderer** — maximum throughput, fully parallel:
///
/// ```swift
/// let images = try await doc.withConcurrentPages { page, _ in
///     let r = PopplerRenderer()   // one per task, no contention
///     r.setAntialiasing(true)
///     return r.renderToData(page: page, xres: 150)
/// }
/// ```
///
/// Choose per-task when rendering is the bottleneck and you have many cores.
/// Choose shared when you want consistent hint settings across all pages without
/// extra allocations.
public final class PopplerRenderer: @unchecked Sendable {

    // The renderer pointer lives inside the Mutex.
    // Hint setters and render calls are the only way to reach it — both go through withLock.
    private let _state: Mutex<PopplerRendererPtr>

    public init() {
        _state = Mutex(poppler_renderer_create())
    }

    deinit {
        _state.withLock { poppler_renderer_delete($0) }
    }

    // MARK: - Render Hints

    /// Enables or disables general (vector/graphics) antialiasing.
    public func setAntialiasing(_ enabled: Bool) {
        _state.withLock { poppler_renderer_set_antialiasing($0, enabled) }
    }

    /// Enables or disables text antialiasing.
    public func setTextAntialiasing(_ enabled: Bool) {
        _state.withLock { poppler_renderer_set_text_antialiasing($0, enabled) }
    }

    /// Enables or disables text hinting (subpixel glyph positioning).
    public func setTextHinting(_ enabled: Bool) {
        _state.withLock { poppler_renderer_set_text_hinting($0, enabled) }
    }

    // MARK: - Raw Pixel Buffer

    /// Renders a page to an uncompressed pixel buffer.
    ///
    /// Safe to call concurrently on a shared renderer — serialised through the
    /// renderer’s lock.  Also safe to mix with `page.text()` on the same page:
    /// acquires `page._lock` before `renderer._state` (consistent order,
    /// no deadlock).
    public func render(
        page: PopplerPage,
        xres: Double = 72.0,
        yres: Double = 72.0
    ) -> PopplerImage? {
        page._lock.withLock { _ in
            _state.withLock { rendererPtr -> PopplerImage? in
                guard
                    let imgPtr = poppler_renderer_render_page(
                        rendererPtr, page.pagePtr, xres, yres
                    )
                else { return nil }
                defer { poppler_image_delete(imgPtr) }
                guard poppler_image_is_valid(imgPtr) else { return nil }
                return PopplerImage(imagePtr: imgPtr)
            }
        }
    }

    // MARK: - Encoded Image Data

    /// Renders a page and encodes it as PNG or JPEG bytes.
    ///
    /// Safe to call concurrently on a shared renderer.  Same lock order as
    /// `render(page:xres:yres:)`.
    public func renderToData(
        page: PopplerPage,
        xres: Double = 150.0,
        yres: Double = 150.0,
        format: PopplerRasterFormat = .png
    ) -> Data? {
        page._lock.withLock { _ in
            _state.withLock { rendererPtr -> Data? in
                guard
                    let imgPtr = poppler_renderer_render_page(
                        rendererPtr, page.pagePtr, xres, yres
                    )
                else { return nil }
                defer { poppler_image_delete(imgPtr) }
                guard poppler_image_is_valid(imgPtr) else { return nil }

                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).\(format.fileExtension)")
                defer { try? FileManager.default.removeItem(at: tmpURL) }

                guard
                    poppler_image_save_to_path(
                        imgPtr, tmpURL.path, format.rawValue, Int32(xres)
                    )
                else { return nil }

                return try? Data(contentsOf: tmpURL)
            }
        }  // page._lock
    }
}
