#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

// MARK: - Text Streaming

/// An `AsyncSequence` that yields the extracted text of each page in document order.
///
/// Obtain via `PopplerDocument.textStream(layout:firstPage:lastPage:)`.
///
/// No separate `Task` is spawned — the caller's task drives iteration directly,
/// giving structured cancellation via `Task.checkCancellation()` and natural
/// back-pressure: the next page is only extracted when the consumer asks for it.
public struct PageTextSequence: AsyncSequence, Sendable {
    public typealias Element = String

    let document: PopplerDocument
    let layout: PopplerTextLayout
    let start: Int
    let end: Int
    let validationError: PopplerError?

    public struct AsyncIterator: AsyncIteratorProtocol {
        let document: PopplerDocument
        let layout: PopplerTextLayout
        var currentPage: Int
        let endPage: Int
        var pendingError: PopplerError?

        /// Extracts and returns the next non-empty page text, or `nil` when exhausted.
        ///
        /// If the page range was invalid at construction time, throws
        /// `PopplerError.invalidPageRange` on the very first call.
        /// Blank / image-only pages are skipped transparently.
        /// Throws `CancellationError` if the enclosing task is cancelled.
        public mutating func next() async throws -> String? {
            if let error = pendingError {
                pendingError = nil
                throw error
            }
            while currentPage <= endPage {
                try Task.checkCancellation()
                let i = currentPage
                currentPage += 1
                let text = try document.page(at: i)
                    .text(layout: layout)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
            return nil
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            document: document,
            layout: layout,
            currentPage: start,
            endPage: end,
            pendingError: validationError
        )
    }
}

// MARK: - Rasterization Streaming

/// An `AsyncSequence` that yields each rasterized page as encoded image `Data`.
///
/// Obtain via `PopplerDocument.rasterStream(xres:yres:format:firstPage:lastPage:)`.
///
/// A single `PopplerRenderer` is allocated when iteration begins (inside
/// `makeAsyncIterator()`) and reused for every page — no separate `Task` is
/// spawned.  Back-pressure and cancellation are both structural.
public struct PageRasterSequence: AsyncSequence, Sendable {
    public typealias Element = Data

    let document: PopplerDocument
    let xres: Double
    let yres: Double
    let format: PopplerRasterFormat
    let start: Int
    let end: Int
    let validationError: PopplerError?

    public struct AsyncIterator: AsyncIteratorProtocol {
        let document: PopplerDocument
        let renderer: PopplerRenderer  // one renderer, reused across all pages
        let xres: Double
        let yres: Double
        let format: PopplerRasterFormat
        var currentPage: Int
        let endPage: Int
        var pendingError: PopplerError?

        /// Renders and returns the next page's encoded image data, or `nil` when exhausted.
        ///
        /// If the page range was invalid at construction time, throws
        /// `PopplerError.invalidPageRange` on the very first call.
        /// Throws `PopplerError.encodingFailed` if encoding fails, or
        /// `CancellationError` if the enclosing task is cancelled.
        public mutating func next() async throws -> Data? {
            if let error = pendingError {
                pendingError = nil
                throw error
            }
            while currentPage <= endPage {
                try Task.checkCancellation()
                let i = currentPage
                currentPage += 1
                let page = try document.page(at: i)
                guard
                    let data = renderer.renderToData(
                        page: page, xres: xres, yres: yres, format: format
                    )
                else {
                    throw PopplerError.encodingFailed
                }
                return data
            }
            return nil
        }
    }

    /// Creates the iterator, allocating a fresh `PopplerRenderer` for this iteration session.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            document: document,
            renderer: PopplerRenderer(),
            xres: xres,
            yres: yres,
            format: format,
            currentPage: start,
            endPage: end,
            pendingError: validationError
        )
    }
}

/// An `AsyncSequence` that yields each rasterized page as a Base64-encoded `String`.
///
/// Obtain via `PopplerDocument.rasterBase64Stream(xres:yres:format:firstPage:lastPage:)`.
/// This type wraps `PageRasterSequence` and applies Base64 encoding inline in `next()`.
public struct PageBase64RasterSequence: AsyncSequence, Sendable {
    public typealias Element = String

    private let base: PageRasterSequence

    init(base: PageRasterSequence) {
        self.base = base
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: PageRasterSequence.AsyncIterator

        public mutating func next() async throws -> String? {
            guard let data = try await base.next() else { return nil }
            return data.base64EncodedString()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator())
    }
}

// MARK: - PopplerDocument streaming extensions

extension PopplerDocument {

    // MARK: Text

    /// Returns an `AsyncSequence` that yields the extracted text of each page.
    ///
    /// Each element is the trimmed, non-empty text of one page.
    /// Blank or image-only pages are silently skipped.
    /// Pages are processed in document order.
    ///
    /// ```swift
    /// for try await pageText in doc.textStream() {
    ///     print(pageText)
    /// }
    /// ```
    ///
    /// If the range is invalid, `PopplerError.invalidPageRange` is thrown on the
    /// first iteration step rather than at the call site, keeping the loop syntax clean.
    ///
    /// - Parameters:
    ///   - layout:    Text-extraction algorithm. Defaults to `.natural`.
    ///   - firstPage: 0-based index of the first page. Defaults to `0`.
    ///   - lastPage:  0-based index of the last page (inclusive). Defaults to the last page.
    public func textStream(
        layout: PopplerTextLayout = .natural,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) -> PageTextSequence {
        let start = firstPage ?? 0
        let end = lastPage ?? max(0, pageCount - 1)
        guard start >= 0, end < pageCount, start <= end else {
            return PageTextSequence(
                document: self, layout: layout,
                start: 0, end: -1,
                validationError: .invalidPageRange
            )
        }
        return PageTextSequence(
            document: self, layout: layout,
            start: start, end: end,
            validationError: nil
        )
    }

    /// Collects the full text of the document into a single `String`.
    ///
    /// Page texts are joined with `"\n"`.
    /// For large documents, prefer `textStream(layout:firstPage:lastPage:)` to avoid
    /// materialising all text in memory simultaneously.
    ///
    /// - Parameters:
    ///   - layout:    Text-extraction algorithm. Defaults to `.natural`.
    ///   - firstPage: 0-based first page. Defaults to `0`.
    ///   - lastPage:  0-based last page (inclusive). Defaults to the last page.
    public func extractText(
        layout: PopplerTextLayout = .natural,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) async throws -> String {
        let start = firstPage ?? 0
        let end = lastPage ?? max(0, pageCount - 1)
        var parts: [String] = []
        if end >= start { parts.reserveCapacity(end - start + 1) }
        for try await text in textStream(layout: layout, firstPage: firstPage, lastPage: lastPage) {
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }

    // MARK: Rasterization

    /// Returns an `AsyncSequence` that yields each rasterized page as encoded image `Data`.
    ///
    /// A single `PopplerRenderer` is created when iteration begins and reused across all pages.
    ///
    /// ```swift
    /// for try await data in doc.rasterStream(xres: 150, format: .jpeg) {
    ///     try await send(data)
    /// }
    /// ```
    ///
    /// If the range is invalid, `PopplerError.invalidPageRange` is thrown on the
    /// first iteration step rather than at the call site, keeping the loop syntax clean.
    ///
    /// - Parameters:
    ///   - xres:      Horizontal DPI. Default `150`.
    ///   - yres:      Vertical DPI. Default `150`.
    ///   - format:    Output image format. Default `.png`.
    ///   - firstPage: 0-based first page. Defaults to `0`.
    ///   - lastPage:  0-based last page (inclusive). Defaults to the last page.
    public func rasterStream(
        xres: Double = 150,
        yres: Double = 150,
        format: PopplerRasterFormat = .png,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) -> PageRasterSequence {
        let start = firstPage ?? 0
        let end = lastPage ?? max(0, pageCount - 1)
        guard start >= 0, end < pageCount, start <= end else {
            return PageRasterSequence(
                document: self, xres: xres, yres: yres, format: format,
                start: 0, end: -1,
                validationError: .invalidPageRange
            )
        }
        return PageRasterSequence(
            document: self, xres: xres, yres: yres, format: format,
            start: start, end: end,
            validationError: nil
        )
    }

    /// Returns an `AsyncSequence` that yields each rasterized page as a Base64-encoded `String`.
    ///
    /// Primary entry point for the scanned-PDF → multimodal LLM pipeline:
    ///
    /// ```swift
    /// guard !doc.hasExtractableText else {
    ///     let text = try await doc.extractText()
    ///     // feed text to LLM
    ///     return
    /// }
    /// for try await b64 in doc.rasterBase64Stream() {
    ///     try await ollama.generate(model: "medgemma:4b-it", image: b64, prompt: "Extract…")
    /// }
    /// ```
    ///
    /// - Parameters: same as `rasterStream(xres:yres:format:firstPage:lastPage:)`.
    public func rasterBase64Stream(
        xres: Double = 150,
        yres: Double = 150,
        format: PopplerRasterFormat = .png,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) -> PageBase64RasterSequence {
        PageBase64RasterSequence(
            base: rasterStream(
                xres: xres, yres: yres, format: format,
                firstPage: firstPage, lastPage: lastPage
            )
        )
    }

    // MARK: Convenience collectors

    /// Rasterizes the requested page range and collects all encoded images as `[Data]`.
    ///
    /// Prefer `rasterStream(...)` for large documents to avoid holding all images in memory.
    public func rasterize(
        xres: Double = 150,
        yres: Double = 150,
        format: PopplerRasterFormat = .png,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) async throws -> [Data] {
        let start = firstPage ?? 0
        let end = lastPage ?? max(0, pageCount - 1)
        var result: [Data] = []
        if end >= start { result.reserveCapacity(end - start + 1) }
        for try await data in rasterStream(
            xres: xres, yres: yres, format: format,
            firstPage: firstPage, lastPage: lastPage
        ) { result.append(data) }
        return result
    }

    /// Rasterizes the requested page range and returns each page as a Base64-encoded `String`.
    ///
    /// Prefer `rasterBase64Stream(...)` for large documents.
    public func rasterizeToBase64(
        xres: Double = 150,
        yres: Double = 150,
        format: PopplerRasterFormat = .png,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) async throws -> [String] {
        let start = firstPage ?? 0
        let end = lastPage ?? max(0, pageCount - 1)
        var result: [String] = []
        if end >= start { result.reserveCapacity(end - start + 1) }
        for try await b64 in rasterBase64Stream(
            xres: xres, yres: yres, format: format,
            firstPage: firstPage, lastPage: lastPage
        ) { result.append(b64) }
        return result
    }
}
