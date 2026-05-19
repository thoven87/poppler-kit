import Foundation

// MARK: - Text Streaming

extension PopplerDocument {

    /// Streams the extracted text of each page as an `AsyncThrowingStream<String, Error>`.
    ///
    /// Each yielded element is the trimmed, non-empty text of one page.
    /// Blank or image-only pages are silently skipped.
    /// Pages are processed in document order, one at a time — no parallel reads.
    ///
    /// **Cancellation:** cancelling the consuming `Task` stops iteration cleanly
    /// before the next page is extracted.
    ///
    /// - Parameters:
    ///   - layout:    Text-extraction algorithm. Defaults to `.natural`.
    ///   - firstPage: 0-based index of the first page to extract. Defaults to `0`.
    ///   - lastPage:  0-based index of the last page (inclusive). Defaults to the last page.
    /// - Throws: `PopplerError.invalidPageRange` if the range is out of bounds.
    public func textStream(
        layout: PopplerTextLayout = .natural,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let start = firstPage ?? 0
                let end = lastPage ?? max(0, pageCount - 1)

                guard start >= 0, end < pageCount, start <= end else {
                    continuation.finish(throwing: PopplerError.invalidPageRange)
                    return
                }
                for i in start...end {
                    guard !Task.isCancelled else { break }
                    do {
                        let text = try page(at: i)
                            .text(layout: layout)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { continuation.yield(text) }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Collects the full text of the document into a single `String`.
    ///
    /// Page texts are joined with a newline separator.
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
        var parts: [String] = []
        for try await text in textStream(layout: layout, firstPage: firstPage, lastPage: lastPage) {
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Rasterization Streaming

extension PopplerDocument {

    /// Streams each rasterized page as encoded image `Data`.
    ///
    /// A single `PopplerRenderer` is created when the stream starts and reused across
    /// all pages.  Each page is rendered and encoded before the next begins, so the
    /// consumer can pipeline work (e.g. sending to a multimodal LLM) without waiting
    /// for the whole document to be processed.
    ///
    /// **Cancellation:** stopping the consuming `Task` terminates the stream cleanly.
    ///
    /// - Parameters:
    ///   - xres:      Horizontal DPI. Default `150` (good OCR / LLM balance).
    ///   - yres:      Vertical DPI. Default `150`.
    ///   - format:    Output image format. Default `.png`.
    ///   - firstPage: 0-based first page. Defaults to `0`.
    ///   - lastPage:  0-based last page (inclusive). Defaults to the last page.
    /// - Throws: `PopplerError.invalidPageRange`, `PopplerError.renderingFailed`,
    ///           or `PopplerError.encodingFailed`.
    public func rasterStream(
        xres: Double = 150,
        yres: Double = 150,
        format: PopplerRasterFormat = .png,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let start = firstPage ?? 0
                let end = lastPage ?? max(0, pageCount - 1)
                let renderer = PopplerRenderer()

                guard start >= 0, end < pageCount, start <= end else {
                    continuation.finish(throwing: PopplerError.invalidPageRange)
                    return
                }
                for i in start...end {
                    guard !Task.isCancelled else { break }
                    do {
                        let p = try page(at: i)
                        guard
                            let data = renderer.renderToData(
                                page: p, xres: xres, yres: yres, format: format
                            )
                        else {
                            continuation.finish(throwing: PopplerError.encodingFailed)
                            return
                        }
                        continuation.yield(data)
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams each rasterized page as a Base64-encoded `String`.
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
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await data in rasterStream(
                        xres: xres, yres: yres, format: format,
                        firstPage: firstPage, lastPage: lastPage
                    ) {
                        guard !Task.isCancelled else { break }
                        continuation.yield(data.base64EncodedString())
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Convenience collectors

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
        var result: [Data] = []
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
        var result: [String] = []
        for try await b64 in rasterBase64Stream(
            xres: xres, yres: yres, format: format,
            firstPage: firstPage, lastPage: lastPage
        ) { result.append(b64) }
        return result
    }
}
