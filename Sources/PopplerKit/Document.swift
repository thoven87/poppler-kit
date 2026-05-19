import CPoppler
import CxxStdlib
import Foundation
import Synchronization

/// A Swift wrapper around a Poppler PDF document.
///
/// Load a document from a file or in-memory `Data`:
/// ```swift
/// let doc = try PopplerDocument.load(from: url)
/// let doc = try PopplerDocument.load(from: data, userPassword: "s3cr3t")
/// ```
///
/// ## Concurrency
///
/// `PopplerDocument` is marked `@unchecked Sendable` — it can be passed across
/// `Task` boundaries, but **not all operations are safe to call concurrently
/// from multiple tasks against the same instance**.
///
/// | Safe from multiple concurrent tasks | Unsafe (race condition) |
/// |---|---|
/// | All read-only properties (`title`, `pageCount`, …) | Sharing a `PopplerPage` across tasks |
/// | `page(at:)` — each call returns a fresh object | Sharing a `PopplerRenderer` across tasks |
/// | Loading separate documents | Calling `save(to:)` concurrently |
///
/// For parallel page processing, use ``withConcurrentPages(_:)`` which
/// guarantees each task receives its own `PopplerPage` instance.
public final class PopplerDocument: @unchecked Sendable {

    // MARK: - Private state

    // The pointer is set once at `init` and never reassigned.  All metadata
    // properties (title, pageCount, isEncrypted, …) read from it lock-free —
    // poppler’s scalar getter functions are safe for concurrent reads on an
    // already-loaded document because they only access pre-initialised state.
    internal let document: PopplerDocPtr

    // Serialises the poppler operations that may update internal caches or
    // modify document state.  Specifically:
    //
    //   • create_page / create_page_by_label  — may write to PageCache
    //   • create_font_iterator               — builds font structures
    //   • create_destination_map             — iterates name tree
    //   • create_toc                         — builds outline tree
    //   • embedded_files                     — iterates attachment list
    //   • unlock / save / save_a_copy        — explicitly modify state
    //
    // Pure scalar metadata reads (get_pages, get_title, is_encrypted, …)
    // do NOT go through this lock — they are genuinely read-only.
    private let _lock = Mutex<Void>(())

    private init(document: PopplerDocPtr) {
        self.document = document
    }

    deinit {
        poppler_delete_document(document)
    }

    // MARK: - Loading

    /// Loads a PDF from a local file URL.
    ///
    /// - Parameters:
    ///   - url:            Local path to the PDF.
    ///   - ownerPassword:  Owner (permissions) password, or `nil` for unencrypted documents.
    ///   - userPassword:   User (open) password, or `nil` if not required.
    /// - Throws: `PopplerError.documentLoadFailed` if the file is missing, corrupt,
    ///   or the supplied password is incorrect.
    ///   Check `isLocked` on the returned document if you suspect partial access.
    public static func load(
        from url: URL,
        ownerPassword: String? = nil,
        userPassword: String? = nil
    ) throws -> PopplerDocument {
        guard
            let ptr = poppler_document_load_from_file_with_password(
                url.path, ownerPassword ?? "", userPassword ?? ""
            )
        else {
            throw PopplerError.documentLoadFailed
        }
        return PopplerDocument(document: ptr)
    }

    /// Loads a PDF from in-memory `Data`.
    ///
    /// - Parameters:
    ///   - data:           Raw PDF bytes. Must be ≤ 2 GB (32-bit length cap in the C++ API).
    ///   - ownerPassword:  Owner password, or `nil` if not required.
    ///   - userPassword:   User password, or `nil` if not required.
    /// - Throws: `PopplerError.documentLoadFailed` if parsing fails or the password is incorrect.
    public static func load(
        from data: Data,
        ownerPassword: String? = nil,
        userPassword: String? = nil
    ) throws -> PopplerDocument {
        precondition(data.count <= Int(Int32.max), "PDF data exceeds the 2 GB limit of the C++ API")
        let ptr: PopplerDocPtr? = data.withUnsafeBytes { buf in
            guard let base = buf.bindMemory(to: CChar.self).baseAddress else { return nil }
            return poppler_document_load_from_raw_data_with_password(
                base, Int32(buf.count),
                ownerPassword ?? "", userPassword ?? ""
            )
        }
        guard let validPtr = ptr else { throw PopplerError.documentLoadFailed }
        return PopplerDocument(document: validPtr)
    }

    // MARK: - Core

    /// Total number of pages in the document.
    public var pageCount: Int { Int(poppler_document_get_pages(document)) }

    /// The PDF specification version (e.g. `(major: 1, minor: 7)` or `(major: 2, minor: 0)`).
    public var pdfVersion: (major: Int, minor: Int) {
        var major: Int32 = 0
        var minor: Int32 = 0
        poppler_document_get_pdf_version(document, &major, &minor)
        return (Int(major), Int(minor))
    }

    // MARK: - Security

    /// `true` if the document uses any form of encryption.
    public var isEncrypted: Bool { poppler_document_is_encrypted(document) }

    /// `true` if the document is encrypted and the current password does not grant full access.
    ///
    /// Text extraction and rendering may still succeed for read-only–restricted documents;
    /// owner-level operations (printing, copying) will be blocked by the viewer.
    public var isLocked: Bool { poppler_document_is_locked(document) }

    /// `true` if the document contains embedded JavaScript.
    ///
    /// JavaScript in PDFs can open URLs, submit forms, or execute arbitrary actions.
    /// Use this as a quick security screen before processing untrusted documents.
    public var hasJavaScript: Bool { poppler_document_has_javascript(document) }

    /// The type of interactive form embedded in this document.
    public var formType: PopplerFormType {
        PopplerFormType(rawValue: poppler_document_get_form_type(document)) ?? .none
    }

    /// The set of operations permitted by the document's security settings.
    ///
    /// For unencrypted documents all permissions are implicitly granted.
    /// Check specific flags before performing sensitive operations:
    /// ```swift
    /// guard doc.permissions.contains(.copy) else { return }
    /// ```
    public var permissions: PopplerPermissions {
        // Maps to poppler::permission_enum values 0–7
        var p = PopplerPermissions()
        if poppler_document_has_permission(document, 0) { p.insert(.print) }
        if poppler_document_has_permission(document, 1) { p.insert(.change) }
        if poppler_document_has_permission(document, 2) { p.insert(.copy) }
        if poppler_document_has_permission(document, 3) { p.insert(.addNotes) }
        if poppler_document_has_permission(document, 4) { p.insert(.fillForms) }
        if poppler_document_has_permission(document, 5) { p.insert(.accessibility) }
        if poppler_document_has_permission(document, 6) { p.insert(.assemble) }
        if poppler_document_has_permission(document, 7) { p.insert(.printHighRes) }
        return p
    }

    /// `true` if the document is linearised ("Fast Web View") — optimised so the first page
    /// can be displayed before the rest of the file is downloaded.
    public var isLinearized: Bool { poppler_document_is_linearized(document) }

    /// `true` if the document has at least one embedded file attachment.
    ///
    /// Use this as a cheap guard before calling `embeddedFiles()` to avoid
    /// allocating the list when there are no attachments.
    public var hasEmbeddedFiles: Bool { poppler_document_has_embedded_files(document) }

    /// Attempts to unlock an encrypted document using the supplied passwords.
    ///
    /// Call this after a successful `load` if `isLocked` is `true` and you have obtained
    /// the password interactively (e.g. from a UI prompt).
    ///
    /// - Returns: `true` if the document is now unlocked.
    @discardableResult
    public func unlock(ownerPassword: String? = nil, userPassword: String? = nil) -> Bool {
        _lock.withLock { _ in
            poppler_document_unlock(document, ownerPassword ?? "", userPassword ?? "")
        }
    }

    // MARK: - Metadata

    /// Document title, or `nil` if not embedded.
    public var title: String? { nilIfEmpty(String(poppler_document_get_title(document))) }

    /// Document author, or `nil` if not embedded.
    public var author: String? { nilIfEmpty(String(poppler_document_get_author(document))) }

    /// Document subject, or `nil` if not embedded.
    public var subject: String? { nilIfEmpty(String(poppler_document_get_subject(document))) }

    /// Keywords embedded in the document, or `nil` if absent.
    public var keywords: String? { nilIfEmpty(String(poppler_document_get_keywords(document))) }

    /// The application that originally created the source document, or `nil` if absent.
    public var creator: String? { nilIfEmpty(String(poppler_document_get_creator(document))) }

    /// The application that converted the document to PDF, or `nil` if absent.
    public var producer: String? { nilIfEmpty(String(poppler_document_get_producer(document))) }

    /// Creation date embedded in the PDF, or `nil` if absent or unparseable.
    public var creationDate: Date? {
        let ts = poppler_document_get_creation_date(document)
        guard ts != -1 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    /// Last-modification date embedded in the PDF, or `nil` if absent.
    public var modificationDate: Date? {
        let ts = poppler_document_get_modification_date(document)
        guard ts != -1 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    /// The raw XMP metadata packet embedded in the document, or `nil` if absent.
    ///
    /// XMP is a richer metadata format than the standard info-dictionary fields
    /// (title, author, etc.) and may contain Dublin Core, IPTC, and custom schemas.
    /// Parse the returned XML string with `XMLDocument` or a dedicated XMP library.
    public var xmpMetadata: String? {
        nilIfEmpty(String(poppler_document_get_metadata(document)))
    }

    /// The document's PDF identifier as `(permanent, update)` hex strings,
    /// or `nil` if the document has no ID entry.
    ///
    /// - `permanent`: assigned when the document is first created; never changes.
    /// - `update`: changes each time the document is saved/updated.
    ///
    /// Together they uniquely identify a specific revision of a document.
    public var pdfID: (permanent: String, update: String)? {
        guard poppler_document_has_pdf_id(document) else { return nil }
        let p = String(poppler_document_get_permanent_id(document))
        let u = String(poppler_document_get_update_id(document))
        guard !p.isEmpty || !u.isEmpty else { return nil }
        return (p, u)
    }

    // MARK: - Viewer hints

    /// Page-layout mode the PDF recommends to viewer applications.
    public var pageLayout: PopplerPageLayout {
        PopplerPageLayout(rawValue: poppler_document_get_page_layout(document)) ?? .none
    }

    /// UI mode the PDF recommends when the document is first opened.
    public var pageMode: PopplerPageMode {
        PopplerPageMode(rawValue: poppler_document_get_page_mode(document)) ?? .none
    }

    // MARK: - Heuristics

    /// `true` if the document appears to contain an embedded text layer.
    ///
    /// Samples up to five pages; returns `true` as soon as any page yields more than
    /// 20 non-whitespace characters.  Returns `false` for image-only (scanned) PDFs.
    /// Route documents where this is `false` to an OCR pipeline.
    public var hasExtractableText: Bool {
        let limit = min(pageCount, 5)
        for i in 0..<limit {
            guard let p = try? page(at: i) else { continue }
            if p.text().trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 {
                return true
            }
        }
        return false
    }

    // MARK: - Structure

    /// Table of Contents (outline) of the document, or `nil` if absent.
    public func tableOfContents() -> PopplerTOCItem? {
        _lock.withLock { _ in
            guard let tocPtr = poppler_document_create_toc(document) else { return nil }
            defer { poppler_delete_toc(tocPtr) }
            guard let rootPtr = poppler_toc_get_root(tocPtr) else { return nil }
            return PopplerTOCItem(itemPtr: rootPtr)
        }
    }

    /// All file attachments embedded in the document.
    public func embeddedFiles() -> [PopplerEmbeddedFile] {
        _lock.withLock { _ in
            let listPtr = poppler_document_get_embedded_files(document)
            defer { poppler_delete_embedded_file_list(listPtr) }
            let size = Int(poppler_embedded_file_list_get_size(listPtr))
            return (0..<size).compactMap { i in
                guard let filePtr = poppler_embedded_file_list_get_item(listPtr, Int32(i)) else {
                    return nil
                }
                return PopplerEmbeddedFile(filePtr: filePtr)
            }
        }
    }

    /// All fonts referenced or embedded in the document.
    public func fonts() -> [PopplerFontInfo] {
        _lock.withLock { _ in
            guard let iterPtr = poppler_document_create_font_iterator(document, 0) else {
                return []
            }
            defer { poppler_delete_font_iterator(iterPtr) }
            var result: [PopplerFontInfo] = []
            while poppler_font_iterator_has_next(iterPtr) {
                guard let listPtr = poppler_font_iterator_next(iterPtr) else { continue }
                defer { poppler_delete_font_info_list(listPtr) }
                let size = Int(poppler_font_info_list_get_size(listPtr))
                for i in 0..<size {
                    guard let fontPtr = poppler_font_info_list_get_item(listPtr, Int32(i)) else {
                        continue
                    }
                    result.append(PopplerFontInfo(fontPtr: fontPtr))
                }
            }
            return result
        }
    }

    /// All named destinations (bookmarks and link targets) in the document.
    public func destinations() -> [PopplerDestination] {
        _lock.withLock { _ in
            guard let mapPtr = poppler_document_create_destination_map(document) else { return [] }
            defer { poppler_delete_destination_map(mapPtr) }
            guard let listPtr = poppler_destination_map_to_list(mapPtr) else { return [] }
            defer { poppler_delete_destination_list(listPtr) }
            let size = Int(poppler_destination_list_get_size(listPtr))
            return (0..<size).compactMap { i in
                let name = String(cString: poppler_destination_list_get_name(listPtr, Int32(i)))
                guard let destPtr = poppler_destination_list_get_dest(listPtr, Int32(i)) else {
                    return nil
                }
                return PopplerDestination(name: name, destPtr: destPtr)
            }
        }
    }

    // MARK: - Page access

    /// Retrieves the page whose logical label matches `label`.
    ///
    /// Logical labels (`"i"`, `"ii"`, `"1"`, `"A-1"`) are what's printed on the
    /// physical page and differ from the 0-based index.
    ///
    /// - Throws: `PopplerError.invalidPage` if no page with that label exists.
    public func page(labeled label: String) throws -> PopplerPage {
        try _lock.withLock { _ in
            guard let ptr = poppler_document_create_page_by_label(document, label) else {
                throw PopplerError.invalidPage
            }
            return PopplerPage(page: ptr)
        }
    }

    /// Retrieves the page at the given 0-based index.
    /// - Throws: `PopplerError.invalidPage` if `index` is out of range.
    public func page(at index: Int) throws -> PopplerPage {
        try _lock.withLock { _ in
            guard index >= 0, index < pageCount else { throw PopplerError.invalidPage }
            guard let ptr = poppler_document_create_page(document, Int32(index)) else {
                throw PopplerError.invalidPage
            }
            return PopplerPage(page: ptr)
        }
    }

    // MARK: - Custom metadata

    /// Returns all keys present in the document's info dictionary.
    ///
    /// Standard keys (`"Title"`, `"Author"`, `"Subject"`, `"Keywords"`, `"Creator"`,
    /// `"Producer"`, `"CreationDate"`, `"ModDate"`) are available as dedicated properties.
    /// Use this method to discover non-standard keys added by the producing application.
    public func infoKeys() -> [String] {
        let listPtr = poppler_document_get_info_keys(document)
        defer { poppler_delete_string_list(listPtr) }
        let count = Int(poppler_string_list_get_size(listPtr))
        return (0..<count).map { String(poppler_string_list_get_item(listPtr, Int32($0))) }
    }

    /// Returns the value for an arbitrary info-dictionary key, or `nil` if absent.
    ///
    /// - Parameter key: Case-sensitive key name (e.g. `"Title"`, `"Keywords"`, `"Company"`).
    public func infoValue(forKey key: String) -> String? {
        nilIfEmpty(String(poppler_document_get_info_key(document, key)))
    }

    // MARK: - Persistence

    /// Saves the document (including any in-memory changes) to the given URL.
    ///
    /// Use `save(to:)` when you've modified metadata and want to write the result back.
    /// - Throws: `PopplerError.saveFailed` if the write operation fails.
    public func save(to url: URL) throws {
        try _lock.withLock { _ in
            guard poppler_document_save(document, url.path) else {
                throw PopplerError.saveFailed
            }
        }
    }

    /// Saves an unmodified, byte-for-byte copy of the document to the given URL.
    ///
    /// More efficient than `save(to:)` when you only need a verbatim copy because
    /// it avoids the overhead of incremental-update serialisation.
    /// - Throws: `PopplerError.saveFailed` if the write operation fails.
    public func saveACopy(to url: URL) throws {
        try _lock.withLock { _ in
            guard poppler_document_save_a_copy(document, url.path) else {
                throw PopplerError.saveFailed
            }
        }
    }

    // MARK: - Async page sequence

    /// An `AsyncSequence` that yields each page in document order.
    public struct PageSequence: AsyncSequence, Sendable {
        public typealias Element = PopplerPage
        let document: PopplerDocument

        public struct AsyncIterator: AsyncIteratorProtocol {
            let document: PopplerDocument
            var index = 0
            public mutating func next() async throws -> PopplerPage? {
                guard index < document.pageCount else { return nil }
                defer { index += 1 }
                return try document.page(at: index)
            }
        }

        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(document: document) }
    }

    /// Iterate over every page as an `AsyncSequence`.
    ///
    /// ```swift
    /// for try await page in document.pages {
    ///     let text = page.text()
    /// }
    /// ```
    public var pages: PageSequence { PageSequence(document: self) }

    // MARK: - Concurrent page processing

    /// Processes every page concurrently and returns results in page order.
    ///
    /// Each task in the group receives its own freshly allocated `PopplerPage`
    /// instance — pages are never shared between tasks.  This is the recommended
    /// pattern for parallel PDF processing:
    ///
    /// ```swift
    /// // Render all pages in parallel
    /// let images: [Data] = try await doc.withConcurrentPages { page, _ in
    ///     let renderer = PopplerRenderer()        // ← one renderer per task
    ///     return renderer.renderToData(page: page, xres: 150, format: .png) ?? Data()
    /// }
    ///
    /// // Extract text from all pages in parallel
    /// let texts: [String] = try await doc.withConcurrentPages { page, index in
    ///     page.text(layout: .physical)
    /// }
    /// ```
    ///
    /// Results are sorted by page index before being returned, regardless of
    /// which task finishes first.
    ///
    /// - Parameter transform: Closure called once per page.  Receives the page
    ///   and its 0-based index.  Must be `@Sendable` — do not capture
    ///   non-`Sendable` state (e.g. a shared `PopplerRenderer`).
    /// - Returns: One `T` per page, in ascending page-index order.
    public func withConcurrentPages<T: Sendable>(
        _ transform: @Sendable @escaping (PopplerPage, Int) async throws -> T
    ) async throws -> [T] {
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            for i in 0..<pageCount {
                group.addTask { [self] in
                    let pg = try self.page(at: i)
                    return try await (i, transform(pg, i))
                }
            }
            var results: [(Int, T)] = []
            results.reserveCapacity(pageCount)
            for try await pair in group { results.append(pair) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: - Private helpers

    private func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}
