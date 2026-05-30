internal import CPopplerBridge

// MARK: - PopplerPage strikethrough detection
//
// Detects text boxes that are visually struck through by a horizontal line segment
// from the page's vector-graphics layer.
//
// Coordinate systems:
//   • lineArtSegments() y-values  — PDF y-UP   (y=0 at page bottom, increases upward)
//   • textBox.boundingBox          — screen y-DOWN (y=0 at page top,  increases downward)
//
// Conversion: screen_y = pageH - pdf_y
// where pageH = cropBox.bottom (the screen-coordinate page height in pt).

extension PopplerPage {

    /// Returns the indices into `textBoxes()` whose text appears struck-through.
    ///
    /// A text box is struck-through when a horizontal line segment from the page's
    /// vector graphics layer:
    ///   1. Passes through the vertical midpoint of the box (within ±20 % of textHeight).
    ///   2. Overlaps the box horizontally by ≥ 80 % of the box's width.
    ///   3. Has a stroke width ≤ 1.3 × textHeight (rejects area fills / table shading).
    ///   4. Is not wider than 1.5 × the text box width (rejects full-page rules).
    ///
    /// Returns an empty set when the page was loaded from raw `Data` (line art is
    /// not available without a file-backed PDFDoc).
    public func strikethroughTextBoxIndices() -> Set<Int> {
        // Filter to horizontal segments only (within 3°)
        let hSegs = lineArtSegments().filter { $0.isHorizontal() }
        guard !hSegs.isEmpty else { return [] }

        let boxes = textBoxes()
        guard !boxes.isEmpty else { return [] }

        // pageH converts PDF y-UP ↔ screen y-DOWN: screen_y = pageH - pdf_y
        let pageH = cropBox.bottom  // screen-coordinate page height

        var result = Set<Int>()

        for (i, box) in boxes.enumerated() {
            let bb = box.boundingBox
            let textH = bb.height  // bottom − top > 0  (screen coords)
            let textW = bb.right - bb.left
            guard textH > 0, textW > 0 else { continue }

            // Vertical midpoint of the text box in screen coords
            let textCenterScreen = (bb.top + bb.bottom) / 2
            let tolerance = textH * 0.20

            for seg in hSegs {
                // (1) Stroke-thickness filter
                if seg.lineWidth > 0, seg.lineWidth / textH > 1.3 { continue }

                // (2) Line-width filter (reject full-page horizontal rules)
                if seg.width / textW > 1.5 { continue }

                // (3) Vertical-center check — convert line's PDF y to screen y
                let lineCenterPDF = (seg.y1 + seg.y2) / 2
                let lineCenterScreen = pageH - lineCenterPDF
                guard abs(lineCenterScreen - textCenterScreen) <= tolerance else { continue }

                // (4) Horizontal-overlap check
                let segL = min(seg.x1, seg.x2)
                let segR = max(seg.x1, seg.x2)
                let oL = max(bb.left, segL)
                let oR = min(bb.right, segR)
                guard oR > oL, (oR - oL) / textW >= 0.80 else { continue }

                result.insert(i)
                break
            }
        }
        return result
    }
}
