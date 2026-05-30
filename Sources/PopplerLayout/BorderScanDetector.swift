#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import PopplerKit

// MARK: - BorderScanDetector
//
// Detects horizontal and vertical border lines in a rendered page image by scanning
// pixel rows / columns for "sufficiently dark" runs.
//
// Use this alongside PopplerRenderer to locate table borders that are drawn as
// graphics (vector lines / filled rectangles) rather than represented in the text
// layer.  The companion `PopplerPage.detectBorderedTables()` convenience wraps the
// full render → scan → grid-extraction pipeline.
//
// Algorithm:
//   1. For each pixel row, count the fraction of pixels whose RGB channels are all
//      ≤ `darkChannelThreshold`.  Rows meeting `lineCoverageThreshold` are candidates.
//   2. Suppress consecutive candidates within `minLineGap` pixels (thick borders).
//   3. Repeat column-wise to find vertical lines.

public enum BorderScanDetector {

    // MARK: - Configuration

    /// Pixels with ALL sampled channels ≤ this value are classified as "dark".
    public static let darkChannelThreshold: UInt8 = 64

    /// Minimum fraction of a row / column that must be dark to count as a border line.
    public static let lineCoverageThreshold: Double = 0.85

    /// Suppress additional detected lines within this many pixels of a previous line
    /// (avoids counting thick borders multiple times).
    public static let minLineGap: Int = 3

    // MARK: - Types

    /// Positions of detected horizontal and vertical border lines in pixel space.
    public struct DetectedLines: Sendable {
        /// Y-pixel positions (0-based, top→bottom) of detected horizontal lines.
        public let horizontal: [Int]
        /// X-pixel positions (0-based, left→right) of detected vertical lines.
        public let vertical: [Int]

        /// Number of row bands between detected horizontal borders.
        /// A pair of horizontal lines produces one row band (N lines → N−1 bands).
        public var gridRows: Int { max(0, horizontal.count - 1) }

        /// Number of column bands between detected vertical borders.
        public var gridColumns: Int { max(0, vertical.count - 1) }
    }

    // MARK: - Public

    /// Detect horizontal and vertical lines in a rendered page image.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - pixels: Raw pixel data, row-major, with `bytesPerRow` stride.
    ///   - format: Pixel format of the data.  `rgb24`, `bgr24`, `argb32`, and `gray8`
    ///     are supported; other formats yield empty results.
    ///   - bytesPerRow: Bytes per row (may include stride padding beyond `width × bpp`).
    /// - Returns: Detected line positions.
    public static func detect(
        width: Int,
        height: Int,
        pixels: Data,
        format: PopplerImageFormat,
        bytesPerRow: Int
    ) -> DetectedLines {
        guard !pixels.isEmpty, width > 0, height > 0 else {
            return DetectedLines(horizontal: [], vertical: [])
        }
        let bpp = bytesPerPixel(for: format)
        guard bpp > 0 else {
            return DetectedLines(horizontal: [], vertical: [])
        }
        let horizontal = scanHorizontal(
            width: width, height: height,
            pixels: pixels, bpp: bpp, bytesPerRow: bytesPerRow
        )
        let vertical = scanVertical(
            width: width, height: height,
            pixels: pixels, bpp: bpp, bytesPerRow: bytesPerRow
        )
        return DetectedLines(horizontal: horizontal, vertical: vertical)
    }

    // MARK: - Private helpers

    private static func bytesPerPixel(for format: PopplerImageFormat) -> Int {
        switch format {
        case .rgb24, .bgr24: return 3
        case .argb32: return 4
        case .gray8: return 1
        case .mono: return 1  // approximated as 1 byte per pixel
        case .invalid: return 0
        }
    }

    /// Returns `true` when the pixel at `offset` has all "colour" channels ≤ threshold.
    /// For 4-byte formats (BGRA on Apple Silicon) bytes 0–2 are the colour channels.
    private static func isDark(_ pixels: Data, at offset: Int, bpp: Int) -> Bool {
        switch bpp {
        case 1:
            return offset < pixels.count
                && pixels[offset] <= darkChannelThreshold
        case 3:
            return offset + 2 < pixels.count
                && pixels[offset] <= darkChannelThreshold
                && pixels[offset + 1] <= darkChannelThreshold
                && pixels[offset + 2] <= darkChannelThreshold
        case 4:
            // BGRA (little-endian argb32): bytes 0–2 = B, G, R; byte 3 = A.
            // Checking 0–2 correctly identifies black with any alpha value.
            return offset + 2 < pixels.count
                && pixels[offset] <= darkChannelThreshold
                && pixels[offset + 1] <= darkChannelThreshold
                && pixels[offset + 2] <= darkChannelThreshold
        default:
            return false
        }
    }

    private static func scanHorizontal(
        width: Int, height: Int,
        pixels: Data, bpp: Int, bytesPerRow: Int
    ) -> [Int] {
        var lines = [Int]()
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            var darkCount = 0
            for x in 0..<width {
                if isDark(pixels, at: rowStart + x * bpp, bpp: bpp) {
                    darkCount += 1
                }
            }
            let coverage = Double(darkCount) / Double(width)
            guard coverage >= lineCoverageThreshold else { continue }
            if let last = lines.last, y - last < minLineGap { continue }
            lines.append(y)
        }
        return lines
    }

    private static func scanVertical(
        width: Int, height: Int,
        pixels: Data, bpp: Int, bytesPerRow: Int
    ) -> [Int] {
        var lines = [Int]()
        for x in 0..<width {
            var darkCount = 0
            for y in 0..<height {
                let offset = y * bytesPerRow + x * bpp
                if isDark(pixels, at: offset, bpp: bpp) {
                    darkCount += 1
                }
            }
            let coverage = Double(darkCount) / Double(height)
            guard coverage >= lineCoverageThreshold else { continue }
            if let last = lines.last, x - last < minLineGap { continue }
            lines.append(x)
        }
        return lines
    }
}

// MARK: - PopplerPage extension

extension PopplerPage {

    /// Detect tables whose cells are delimited by drawn border lines (graphics layer).
    ///
    /// Renders the page at `xres` DPI, then scans the raster image for solid
    /// horizontal and vertical lines with ``BorderScanDetector``.  Any N×M grid
    /// formed by ≥ 2 horizontal and ≥ 2 vertical lines is reported as a table.
    ///
    /// This complements ``detectTables()`` (which works on the text layer) — the
    /// two methods are best combined for documents with both drawn borders and a
    /// text layer.
    ///
    /// - Parameter xres: Rendering resolution in DPI.  Default 72 is sufficient for
    ///   line detection; increase to 144–300 for high-fidelity borders on complex pages.
    /// - Returns: One ``PDFTable`` per detected bordered grid, with synthetic column
    ///   headers (`Col1`, `Col2`, …).  Returns an empty array when rendering fails or
    ///   no bordered grid is found.
    public func detectBorderedTables(xres: Double = 72.0) -> [PDFTable] {
        let renderer = PopplerRenderer()
        guard let image = renderer.render(page: self, xres: xres, yres: xres) else {
            return []
        }
        let lines = BorderScanDetector.detect(
            width: image.width,
            height: image.height,
            pixels: image.data,
            format: image.format,
            bytesPerRow: image.bytesPerRow
        )
        guard lines.gridRows >= 1, lines.gridColumns >= 1 else { return [] }

        // Build a placeholder PDFTable from the detected grid dimensions.
        // Callers needing actual cell text should combine this with detectTables()
        // or extract text within each detected cell region manually.
        let colCount = lines.gridColumns
        let rowCount = lines.gridRows
        let headers = (0..<colCount).map { "Col\($0 + 1)" }
        let rows: [PDFTable.Row] = (0..<rowCount).map { _ in
            PDFTable.Row(
                cells: Dictionary(
                    uniqueKeysWithValues: headers.map { ($0, "") }
                ))
        }
        return [PDFTable(headers: headers, rows: rows)]
    }
}
