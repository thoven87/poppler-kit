import PopplerKit

// MARK: - HiddenTextFilter
//
// Removes LayoutTextLine objects whose bounding boxes overlap significantly
// with regions of PDF-invisible text (render mode 3). Adversarial PDFs embed
// invisible text to inject system prompts into LLM pipelines ("prompt injection");
// filtering before layout analysis prevents those strings from reaching
// extractLayoutText() output.

public enum HiddenTextFilter {

    /// Minimum fraction of a text line's area that must overlap with an
    /// invisible-text bbox for the line to be considered hidden.
    public static let overlapThreshold: Double = 0.3

    // MARK: - Public

    /// Filter invisible text from a page's layout lines.
    ///
    /// - Parameters:
    ///   - lines: The visual text lines for this page.
    ///   - page: The source page (used to fetch invisible text bboxes).
    /// - Returns: Lines with invisible content removed or flagged.
    public static func filter(
        lines: [LayoutTextLine],
        page: PopplerPage
    ) -> (visible: [LayoutTextLine], invisibleCount: Int) {
        let invisibleBoxes = page.invisibleTextBoundingBoxes()
        guard !invisibleBoxes.isEmpty else { return (lines, 0) }

        var visible = [LayoutTextLine]()
        var hiddenCount = 0

        for line in lines {
            if isHidden(line: line, invisibleBoxes: invisibleBoxes) {
                hiddenCount += 1
            } else {
                visible.append(line)
            }
        }
        return (visible, hiddenCount)
    }

    // MARK: - Private

    private static func isHidden(
        line: LayoutTextLine,
        invisibleBoxes: [PopplerRect]
    ) -> Bool {
        let lineArea = line.boundingBox.width * line.boundingBox.height
        guard lineArea > 0 else { return false }

        for iBox in invisibleBoxes {
            let overlapArea = intersectionArea(line.boundingBox, iBox)
            if overlapArea / lineArea >= overlapThreshold { return true }
        }
        return false
    }

    private static func intersectionArea(_ a: PopplerRect, _ b: PopplerRect) -> Double {
        let left = max(a.left, b.left)
        let right = min(a.right, b.right)
        let bottom = max(a.bottom, b.bottom)
        let top = min(a.top, b.top)
        guard right > left, top > bottom else { return 0 }
        return (right - left) * (top - bottom)
    }
}
