import Foundation

// MARK: - Errors

public enum PopplerUtilsError: Error, CustomStringConvertible {
    case processFailed(status: Int32, stderr: String)
    case launchFailed(underlying: Error)
    case binaryNotFound(String)
    case noOutputFiles

    public var description: String {
        switch self {
        case .processFailed(let s, let e):
            return "poppler-utils exited \(s): \(e.isEmpty ? "(no stderr)" : e)"
        case .launchFailed(let err):
            return "Failed to launch poppler-utils binary: \(err)"
        case .binaryNotFound(let name):
            return "'\(name)' not found — install poppler-utils (apt-get/brew)"
        case .noOutputFiles:
            return "Tool produced no output files — PDF may be empty or encrypted"
        }
    }
}

// MARK: - Shared result types

/// Metadata returned by `pdfinfo`.
public struct PDFInfo: Sendable {
    public let title: String?
    public let subject: String?
    public let keywords: String?
    public let author: String?
    public let creator: String?
    public let producer: String?
    public let creationDate: String?
    public let modificationDate: String?
    public let tagged: Bool
    public let form: String  // "none", "AcroForm", "XFA"
    public let hasJavaScript: Bool
    public let pageCount: Int
    public let encrypted: Bool
    public let optimized: Bool
    public let pdfVersion: String
    public let fileSizeBytes: Int?
    /// The complete unmodified stdout of `pdfinfo`.
    public let rawOutput: String
}

/// One font entry returned by `pdffonts`.
public struct PDFFontEntry: Sendable {
    public let name: String
    public let type: String
    public let encoding: String
    public let isEmbedded: Bool
    public let isSubset: Bool
    public let hasUnicode: Bool
}

// MARK: - PopplerUtils

/// Subprocess wrapper around all `poppler-utils` CLI tools.
///
/// Use alongside `PopplerKit` (C++ binding) to reach operations outside
/// `libpoppler-cpp`: split, merge, embedded-image extraction, HTML/SVG/PS/EPS
/// rendering, PostScript export, plain-text extraction, font listing, metadata
/// inspection, and digital-signature signing.
///
/// ## Requirements
/// ```sh
/// apt-get install poppler-utils   # Debian / Ubuntu / Cloud Run
/// brew install poppler            # macOS
/// ```
public struct PopplerUtils: Sendable {

    // MARK: - Binary resolution

    private static let searchPaths = ["/usr/bin", "/opt/homebrew/bin", "/usr/local/bin"]

    private static func resolve(_ name: String) throws -> String {
        guard
            let path =
                searchPaths
                .map({ "\($0)/\(name)" })
                .first(where: { FileManager.default.fileExists(atPath: $0) })
        else { throw PopplerUtilsError.binaryNotFound(name) }
        return path
    }

    // MARK: - Subprocess runner

    @discardableResult
    private static func run(_ binary: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.terminationHandler = { proc in
                let stdout =
                    String(
                        data: out.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8) ?? ""
                let stderr =
                    (String(
                        data: err.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    continuation.resume(
                        throwing: PopplerUtilsError.processFailed(
                            status: proc.terminationStatus, stderr: stderr))
                }
            }
            do { try process.run() } catch {
                continuation.resume(throwing: PopplerUtilsError.launchFailed(underlying: error))
            }
        }
    }

    // =========================================================================
    // MARK: - pdfattach
    // =========================================================================

    /// Attaches a file to a PDF document and writes the result to `outputURL`.
    ///
    /// - Parameters:
    ///   - fileURL:   The file to embed as an attachment.
    ///   - pdfURL:    The source PDF.
    ///   - outputURL: Destination path for the new PDF with the attachment added.
    ///   - replace:   If `true`, replaces an existing attachment with the same name.
    public static func attach(
        file fileURL: URL,
        to pdfURL: URL,
        output outputURL: URL,
        replace: Bool = false
    ) async throws {
        var args: [String] = []
        if replace { args.append("-replace") }
        args += [pdfURL.path, fileURL.path, outputURL.path]
        try await run(resolve("pdfattach"), arguments: args)
    }

    // =========================================================================
    // MARK: - pdfdetach
    // =========================================================================

    /// Extracts a single embedded attachment by its 1-based index.
    ///
    /// Use `PopplerDocument.embeddedFiles()` from `PopplerKit` for in-process
    /// access when `libpoppler-cpp` is available; this method is the CLI fallback.
    ///
    /// - Parameters:
    ///   - number:    1-based index of the embedded file (use `-list` output to find it).
    ///   - pdfURL:    The source PDF.
    ///   - outputURL: Destination path for the extracted file.
    public static func extractAttachment(
        number: Int,
        from pdfURL: URL,
        to outputURL: URL
    ) async throws {
        let args = ["-save", String(number), "-o", outputURL.path, pdfURL.path]
        try await run(resolve("pdfdetach"), arguments: args)
    }

    /// Extracts all embedded attachments into `outputDirectory` (created automatically).
    ///
    /// - Returns: URLs of all extracted files, sorted by filename.
    public static func extractAllAttachments(
        from pdfURL: URL,
        into outputDirectory: URL
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        // pdfdetach -saveall writes to the current working directory;
        // we temporarily set it so files land in outputDirectory.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try resolve("pdfdetach"))
        process.arguments = ["-saveall", pdfURL.path]
        process.currentDirectoryURL = outputDirectory
        let err = Pipe()
        process.standardError = err
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let e =
                        (String(
                            data: err.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(
                        throwing: PopplerUtilsError.processFailed(
                            status: proc.terminationStatus, stderr: e))
                }
            }
            do { try process.run() } catch {
                cont.resume(throwing: PopplerUtilsError.launchFailed(underlying: error))
            }
        }
        return
            (try? FileManager.default.contentsOfDirectory(
                at: outputDirectory, includingPropertiesForKeys: nil))?
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    // =========================================================================
    // MARK: - pdffonts
    // =========================================================================

    /// Lists all fonts referenced or embedded in a PDF.
    ///
    /// Prefer `PopplerDocument.fonts()` from `PopplerKit` when `libpoppler-cpp`
    /// is available — this is the CLI fallback that also works on systems with
    /// only `poppler-utils` installed.
    ///
    /// - Parameters:
    ///   - pdfURL:    The source PDF.
    ///   - firstPage: 1-based first page to examine. Defaults to page 1.
    ///   - lastPage:  1-based last page (inclusive). Defaults to the last page.
    public static func listFonts(
        in pdfURL: URL,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) async throws -> [PDFFontEntry] {
        var args: [String] = []
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        args.append(pdfURL.path)
        let output = try await run(resolve("pdffonts"), arguments: args)
        return parseFontsOutput(output)
    }

    private static func parseFontsOutput(_ text: String) -> [PDFFontEntry] {
        // Skip the header (first 2 lines: column names + separator)
        let lines = text.components(separatedBy: .newlines).dropFirst(2)
        return lines.compactMap { line -> PDFFontEntry? in
            guard line.count > 70 else { return nil }
            // Fixed-width columns from pdffonts output
            let name = String(line.prefix(37)).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let rest = line.dropFirst(37)
            let type = String(rest.prefix(18)).trimmingCharacters(in: .whitespaces)
            let rest2 = rest.dropFirst(18)
            let encoding = String(rest2.prefix(17)).trimmingCharacters(in: .whitespaces)
            let rest3 = rest2.dropFirst(17)
            let flags = rest3.prefix(12).split(separator: " ").map(String.init)
            return PDFFontEntry(
                name: name,
                type: type,
                encoding: encoding,
                isEmbedded: flags.indices.contains(0) && flags[0] == "yes",
                isSubset: flags.indices.contains(1) && flags[1] == "yes",
                hasUnicode: flags.indices.contains(2) && flags[2] == "yes"
            )
        }
    }

    // =========================================================================
    // MARK: - pdfinfo
    // =========================================================================

    /// Returns metadata and structural information about a PDF.
    ///
    /// Prefer the individual properties on `PopplerDocument` from `PopplerKit`
    /// when `libpoppler-cpp` is available.
    ///
    /// - Parameters:
    ///   - pdfURL:        The source PDF.
    ///   - ownerPassword: Owner password, if any.
    ///   - userPassword:  User password, if any.
    public static func info(
        pdfURL: URL,
        ownerPassword: String? = nil,
        userPassword: String? = nil
    ) async throws -> PDFInfo {
        var args: [String] = []
        if let op = ownerPassword { args += ["-opw", op] }
        if let up = userPassword { args += ["-upw", up] }
        args.append(pdfURL.path)
        let output = try await run(resolve("pdfinfo"), arguments: args)
        return parsePDFInfo(output)
    }

    private static func parsePDFInfo(_ text: String) -> PDFInfo {
        func field(_ key: String) -> String? {
            for line in text.components(separatedBy: .newlines) {
                guard line.hasPrefix(key + ":") else { continue }
                let val = String(line.dropFirst(key.count + 1))
                    .trimmingCharacters(in: .whitespaces)
                return val.isEmpty ? nil : val
            }
            return nil
        }
        func bool(_ key: String) -> Bool { field(key)?.lowercased() == "yes" }
        let pages = field("Pages").flatMap(Int.init) ?? 0
        // "File size:  12345 bytes" → strip " bytes"
        let fileSizeStr = field("File size")?.components(separatedBy: " ").first
        return PDFInfo(
            title: field("Title"),
            subject: field("Subject"),
            keywords: field("Keywords"),
            author: field("Author"),
            creator: field("Creator"),
            producer: field("Producer"),
            creationDate: field("CreationDate"),
            modificationDate: field("ModDate"),
            tagged: bool("Tagged"),
            form: field("Form") ?? "none",
            hasJavaScript: bool("JavaScript"),
            pageCount: pages,
            encrypted: bool("Encrypted"),
            optimized: bool("Optimized"),
            pdfVersion: field("PDF version") ?? "",
            fileSizeBytes: fileSizeStr.flatMap(Int.init),
            rawOutput: text
        )
    }

    // =========================================================================
    // MARK: - pdfimages
    // =========================================================================

    /// The output encoding for `pdfimages`.
    public enum EmbeddedImageFormat: Sendable {
        case png  // lossless; used for non-JPEG embedded images
        case jpeg  // native JPEG without re-compression
        case all  // each image in its native format
    }

    /// Extracts embedded raster images (not page rasterisations) from a PDF.
    ///
    /// Output files are named `img-NNN.ext` inside `outputDirectory`.
    /// **The caller is responsible for deleting `outputDirectory` when done.**
    public static func extractEmbeddedImages(
        from pdfURL: URL,
        into outputDirectory: URL,
        format: EmbeddedImageFormat = .png,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        var args: [String] = []
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        switch format {
        case .png: args.append("-png")
        case .jpeg: args.append("-j")
        case .all: args.append("-all")
        }
        args += [pdfURL.path, outputDirectory.appendingPathComponent("img").path]
        try await run(resolve("pdfimages"), arguments: args)
        let validExt = Set(["png", "jpg", "ppm", "pbm", "tif", "ccitt"])
        return
            (try? FileManager.default.contentsOfDirectory(
                at: outputDirectory, includingPropertiesForKeys: nil))?
            .filter { validExt.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    // =========================================================================
    // MARK: - pdfseparate
    // =========================================================================

    /// Splits a PDF into individual single-page PDF files.
    ///
    /// Output files are named `page-000001.pdf`, `page-000002.pdf`, etc.
    /// **The caller is responsible for deleting `outputDirectory` when done.**
    public static func separatePages(
        from pdfURL: URL,
        into outputDirectory: URL,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        var args: [String] = []
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        args += [
            pdfURL.path,
            outputDirectory.appendingPathComponent("page").path + "-%06d.pdf",
        ]
        try await run(resolve("pdfseparate"), arguments: args)
        let pages =
            (try? FileManager.default.contentsOfDirectory(
                at: outputDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        guard !pages.isEmpty else { throw PopplerUtilsError.noOutputFiles }
        return pages
    }

    // =========================================================================
    // MARK: - pdfsig  (verification + signing)
    // =========================================================================

    /// A digital signature found in a PDF document.
    public struct SignatureInfo: Sendable {
        public let number: Int
        public let signerName: String?
        public let signingTime: String?
        public let validationStatus: String
        public let isValid: Bool
    }

    /// Lists and verifies the digital signatures in a PDF.
    ///
    /// Full chain validation requires a configured NSS certificate database;
    /// without one, signer identity is still listed from the embedded certificate.
    ///
    /// - Parameters:
    ///   - pdfURL:   The source PDF.
    ///   - nssCertDB: Path to an NSS certificate database directory (optional).
    ///   - nocert:   Skip certificate chain validation (useful for offline environments).
    public static func listSignatures(
        in pdfURL: URL,
        nssCertDB: URL? = nil,
        nocert: Bool = false
    ) async throws -> [SignatureInfo] {
        var args: [String] = []
        if let db = nssCertDB { args += ["-nssdir", db.path] }
        if nocert { args.append("-nocert") }
        args.append(pdfURL.path)
        let output = try await run(resolve("pdfsig"), arguments: args)
        return parseSignatureOutput(output)
    }

    /// Signs a PDF document using a certificate from an NSS database.
    ///
    /// To add a new signature field: pass `fieldName: nil`.
    /// To sign an existing field: pass `fieldName` with the field name or number.
    ///
    /// - Parameters:
    ///   - pdfURL:           The source PDF.
    ///   - outputURL:        Destination path for the signed PDF.
    ///   - certificateNick:  Nickname (or fingerprint) of the signing certificate in the NSS DB.
    ///   - nssCertDB:        Path to the NSS certificate database directory.
    ///   - nssPassword:      Password for the NSS database, if required.
    ///   - fieldName:        Existing signature field name or number to sign.
    ///                       Pass `nil` to add a new field and sign it.
    ///   - reason:           Reason for signing (embedded in the signature metadata).
    ///   - digest:           Hash algorithm name. Default: `"SHA256"`.
    ///   - etsi:             Use ETSI.CAdES.detached instead of adbe.pkcs7.detached.
    public static func sign(
        pdfURL: URL,
        outputURL: URL,
        certificateNick: String,
        nssCertDB: URL,
        nssPassword: String? = nil,
        fieldName: String? = nil,
        reason: String? = nil,
        digest: String = "SHA256",
        etsi: Bool = false
    ) async throws {
        var args: [String] = ["-nssdir", nssCertDB.path, "-nick", certificateNick]
        if let pwd = nssPassword { args += ["-nss-pwd", pwd] }
        if let r = reason { args += ["-reason", r] }
        if digest != "SHA256" { args += ["-digest", digest] }
        if etsi { args.append("-etsi") }
        if let field = fieldName {
            args += ["-sign", field]
        } else {
            args.append("-add-signature")
        }
        args += [pdfURL.path, outputURL.path]
        try await run(resolve("pdfsig"), arguments: args)
    }

    private static func parseSignatureOutput(_ text: String) -> [SignatureInfo] {
        var sigs: [SignatureInfo] = []
        var current: [String: String] = [:]
        var number = 0
        func flush() {
            guard !current.isEmpty else { return }
            number += 1
            let status = current["Signature Validation Status"] ?? ""
            sigs.append(
                SignatureInfo(
                    number: number,
                    signerName: current["Signer Certificate Common Name"],
                    signingTime: current["Signing Time"],
                    validationStatus: status,
                    isValid: status.contains("SIGNATURE_VALID")
                ))
            current = [:]
        }
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Signature #") {
                flush()
            } else if let i = t.firstIndex(of: ":") {
                current[String(t[..<i]).trimmingCharacters(in: .whitespaces)] =
                    String(t[t.index(after: i)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        flush()
        return sigs
    }

    // =========================================================================
    // MARK: - pdftocairo  (SVG, PS, EPS, PDF, PNG, JPEG, TIFF)
    // =========================================================================

    /// Raster image format for `pdftocairo` and `pdftoppm`.
    public enum RasterFormat: Sendable {
        case png, jpeg, tiff
        var flag: String {
            switch self {
            case .png: "-png"
            case .jpeg: "-jpeg"
            case .tiff: "-tiff"
            }
        }
        var ext: String {
            switch self {
            case .png: "png"
            case .jpeg: "jpg"
            case .tiff: "tif"
            }
        }
    }

    /// Renders pages to raster images using Cairo.
    ///
    /// Outputs one file per page: `base-1.png`, `base-2.png`, etc.
    /// **The caller is responsible for deleting the directory when done.**
    ///
    /// - Parameters:
    ///   - pdfURL:          Source PDF.
    ///   - outputBase:      Base path; page numbers and extension are appended.
    ///   - format:          `.png`, `.jpeg`, or `.tiff`.
    ///   - resolution:      DPI. Default 150.
    ///   - grayscale:       Render in grayscale.
    ///   - transparent:     Use transparent background (PNG only).
    ///   - firstPage:       1-based first page. Defaults to page 1.
    ///   - lastPage:        1-based last page. Defaults to the last page.
    /// - Returns: Sorted URLs of generated image files.
    public static func renderPagesCairo(
        pdfURL: URL,
        outputBase: URL,
        format: RasterFormat,
        resolution: Int = 150,
        grayscale: Bool = false,
        transparent: Bool = false,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) async throws -> [URL] {
        let dir = outputBase.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var args = [format.flag, "-r", String(resolution)]
        if grayscale { args.append("-gray") }
        if transparent { args.append("-transp") }
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        args += [pdfURL.path, outputBase.path]
        try await run(resolve("pdftocairo"), arguments: args)
        return
            (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == format.ext }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    /// Renders a PDF to SVG (one file per page via Cairo).
    public static func convertToSVG(
        pdfURL: URL, outputBase: URL,
        firstPage: Int? = nil, lastPage: Int? = nil
    ) async throws {
        var args = ["-svg"]
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        args += [pdfURL.path, outputBase.path]
        try await run(resolve("pdftocairo"), arguments: args)
    }

    /// Renders a PDF to PostScript via Cairo.
    public static func convertToPostScript(
        pdfURL: URL, outputURL: URL,
        firstPage: Int? = nil, lastPage: Int? = nil,
        level3: Bool = true
    ) async throws {
        var args: [String] = ["-ps"]
        if !level3 { args.append("-level2") }
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        args += [pdfURL.path, outputURL.path]
        try await run(resolve("pdftocairo"), arguments: args)
    }

    /// Renders a single page to EPS via Cairo.
    public static func convertToEPS(
        pdfURL: URL, outputURL: URL, page: Int = 1
    ) async throws {
        let args = [
            "-eps", "-f", String(page), "-l", String(page),
            pdfURL.path, outputURL.path,
        ]
        try await run(resolve("pdftocairo"), arguments: args)
    }

    /// Re-exports a PDF via Cairo (useful for sanitising or subsetting page ranges).
    public static func convertToPDF(
        pdfURL: URL, outputURL: URL,
        firstPage: Int? = nil, lastPage: Int? = nil
    ) async throws {
        var args = ["-pdf"]
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        args += [pdfURL.path, outputURL.path]
        try await run(resolve("pdftocairo"), arguments: args)
    }

    // =========================================================================
    // MARK: - pdftohtml
    // =========================================================================

    /// Converts a PDF to HTML using poppler's built-in HTML exporter.
    ///
    /// Outputs an HTML file (and supporting assets) into `outputDirectory`.
    ///
    /// - Parameters:
    ///   - pdfURL:          Source PDF.
    ///   - outputDirectory: Directory for the generated HTML and image assets.
    ///   - firstPage:       1-based first page. Defaults to page 1.
    ///   - lastPage:        1-based last page. Defaults to the last page.
    ///   - singleFile:      Merge all pages into one HTML file.
    ///   - ignoreImages:    Omit embedded images from the output.
    ///   - zoom:            Scale factor for the output (default 1.5).
    ///   - noFrames:        Generate a frameless HTML document.
    /// - Returns: URL of the main HTML file.
    public static func convertToHTML(
        pdfURL: URL,
        outputDirectory: URL,
        firstPage: Int? = nil,
        lastPage: Int? = nil,
        singleFile: Bool = false,
        ignoreImages: Bool = false,
        zoom: Double = 1.5,
        noFrames: Bool = true
    ) async throws -> URL {
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        let stem = pdfURL.deletingPathExtension().lastPathComponent
        let outputBase = outputDirectory.appendingPathComponent(stem)
        var args: [String] = ["-q"]
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        if singleFile { args.append("-s") }
        if ignoreImages { args.append("-i") }
        if noFrames { args.append("-noframes") }
        if zoom != 1.5 { args += ["-zoom", String(zoom)] }
        args += [pdfURL.path, outputBase.path]
        try await run(resolve("pdftohtml"), arguments: args)
        // pdftohtml appends .html to the output base
        return outputBase.appendingPathExtension("html")
    }

    // =========================================================================
    // MARK: - pdftoppm  (poppler's own raster renderer, complement to pdftocairo)
    // =========================================================================

    /// Renders PDF pages to raster images using poppler's built-in renderer.
    ///
    /// Output files are named `page-NNN.ext` inside `outputDirectory`.
    /// **The caller is responsible for deleting `outputDirectory` when done.**
    ///
    /// Prefer `renderPagesCairo(...)` (which uses Cairo) when colour accuracy
    /// and transparency matter.  Use `renderPages(...)` when you need PPM format
    /// or when Cairo is not available.
    public static func renderPages(
        pdfURL: URL,
        into outputDirectory: URL,
        format: RasterFormat = .png,
        resolution: Int = 150,
        grayscale: Bool = false,
        firstPage: Int? = nil,
        lastPage: Int? = nil,
        scaleToMaxPixels: Int? = nil
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        let prefix = outputDirectory.appendingPathComponent("page").path
        var args: [String] = ["-r", String(resolution)]
        switch format {
        case .png: args.append("-png")
        case .jpeg: args.append("-jpeg")
        case .tiff: break  // pdftoppm has no native TIFF; fall back to PPM
        }
        if grayscale { args.append("-gray") }
        if let max = scaleToMaxPixels { args += ["-scale-to", String(max)] }
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        args += [pdfURL.path, prefix]
        try await run(resolve("pdftoppm"), arguments: args)
        let ext = format == .jpeg ? "jpg" : format == .png ? "png" : "ppm"
        return
            (try? FileManager.default.contentsOfDirectory(
                at: outputDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == ext }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    // =========================================================================
    // MARK: - pdftops  (poppler's own PostScript exporter)
    // =========================================================================

    /// PostScript language level for `pdftops`.
    public enum PostScriptLevel: Sendable {
        case level1, level2, level3
        var flag: String {
            switch self {
            case .level1: return "-level1"
            case .level2: return "-level2"
            case .level3: return "-level3"
            }
        }
    }

    /// Converts a PDF to PostScript using poppler's own PS exporter.
    ///
    /// This is distinct from `convertToPostScript(...)` which uses Cairo.
    /// Use this method when you need fine-grained PS level control or
    /// compatibility with older PostScript workflows.
    ///
    /// - Parameters:
    ///   - pdfURL:    Source PDF.
    ///   - outputURL: Destination `.ps` file.
    ///   - level:     PostScript language level. Default `.level3`.
    ///   - firstPage: 1-based first page. Defaults to page 1.
    ///   - lastPage:  1-based last page. Defaults to the last page.
    ///   - eps:       Generate EPS output (single-page only).
    public static func exportToPostScript(
        pdfURL: URL,
        outputURL: URL,
        level: PostScriptLevel = .level3,
        firstPage: Int? = nil,
        lastPage: Int? = nil,
        eps: Bool = false
    ) async throws {
        var args = [level.flag]
        if eps { args.append("-eps") }
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        args += [pdfURL.path, outputURL.path]
        try await run(resolve("pdftops"), arguments: args)
    }

    // =========================================================================
    // MARK: - pdftotext
    // =========================================================================

    /// Text layout option for `pdftotext`.
    public enum TextLayout: Sendable {
        /// Default reading order (re-flows text into paragraphs).
        case `default`
        /// Preserve the original physical layout (`-layout`). Matches `pdftotext -layout`.
        case physical
        /// Content-stream order, no re-ordering (`-raw`).
        case raw
        /// Tabular mode — fixed-pitch columns (`-fixed`).
        case fixed(columnWidth: Double)
    }

    /// Extracts all text from a PDF as a single `String`.
    ///
    /// Prefer `PopplerDocument.extractText(layout:)` from `PopplerKit` for
    /// in-process extraction with streaming support.  Use this method on systems
    /// where only `poppler-utils` is installed.
    ///
    /// - Parameters:
    ///   - pdfURL:        Source PDF.
    ///   - layout:        Text extraction algorithm.
    ///   - firstPage:     1-based first page. Defaults to page 1.
    ///   - lastPage:      1-based last page. Defaults to the last page.
    ///   - noPageBreaks:  Suppress form-feed characters between pages.
    ///   - ownerPassword: Owner password for encrypted PDFs.
    ///   - userPassword:  User password for encrypted PDFs.
    public static func extractText(
        from pdfURL: URL,
        layout: TextLayout = .default,
        firstPage: Int? = nil,
        lastPage: Int? = nil,
        noPageBreaks: Bool = false,
        ownerPassword: String? = nil,
        userPassword: String? = nil
    ) async throws -> String {
        var args: [String] = []
        switch layout {
        case .default: break
        case .physical: args.append("-layout")
        case .raw: args.append("-raw")
        case .fixed(let w): args += ["-fixed", String(w)]
        }
        if noPageBreaks { args.append("-nopgbrk") }
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        if let op = ownerPassword { args += ["-opw", op] }
        if let up = userPassword { args += ["-upw", up] }
        args += [pdfURL.path, "-"]  // "-" = write to stdout
        return try await run(resolve("pdftotext"), arguments: args)
    }

    /// Extracts text to a file on disk.
    ///
    /// - Parameters:
    ///   - pdfURL:    Source PDF.
    ///   - outputURL: Destination text file (`.txt` recommended).
    ///   - layout:    Text extraction algorithm.
    ///   - firstPage: 1-based first page.
    ///   - lastPage:  1-based last page.
    public static func extractText(
        from pdfURL: URL,
        to outputURL: URL,
        layout: TextLayout = .default,
        firstPage: Int? = nil,
        lastPage: Int? = nil
    ) async throws {
        var args: [String] = []
        switch layout {
        case .default: break
        case .physical: args.append("-layout")
        case .raw: args.append("-raw")
        case .fixed(let w): args += ["-fixed", String(w)]
        }
        if let f = firstPage { args += ["-f", String(f)] }
        if let l = lastPage { args += ["-l", String(l)] }
        args += [pdfURL.path, outputURL.path]
        try await run(resolve("pdftotext"), arguments: args)
    }

    // =========================================================================
    // MARK: - pdfunite
    // =========================================================================

    /// Merges multiple PDF files into a single output PDF, in the order supplied.
    public static func mergePDFs(_ urls: [URL], to outputURL: URL) async throws {
        guard !urls.isEmpty else { return }
        try await run(resolve("pdfunite"), arguments: urls.map(\.path) + [outputURL.path])
    }
}
