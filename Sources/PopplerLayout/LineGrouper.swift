import PopplerKit

// MARK: - LineGrouper
//
// Merges PopplerTextBox items that share the same visual baseline into
// LayoutTextLine values.  Boxes must be supplied in reading order
// (use XYCutSorter first).
//
// Heuristic: two boxes belong to the same line when their Y-centre
// difference is less than the maximum of their font sizes × 0.5.
// Two boxes belong to the same line when their Y-centre difference is less than
// half the maximum of their font sizes — equivalent to a 0.75 same-line probability.

public enum LineGrouper {

    /// Fraction of font size used as the Y-centre tolerance for same-line detection.
    static let yToleranceRatio: Double = 0.5

    // MARK: - Public

    /// Group sorted text boxes into visual lines.
    public static func group(_ boxes: [PopplerTextBox]) -> [LayoutTextLine] {
        guard !boxes.isEmpty else { return [] }

        var lines: [LayoutTextLine] = []
        var current: [PopplerTextBox] = [boxes[0]]

        for box in boxes.dropFirst() {
            if sameLine(current, candidate: box) {
                current.append(box)
            } else {
                lines.append(LayoutTextLine(boxes: sortedByX(current)))
                current = [box]
            }
        }
        lines.append(LayoutTextLine(boxes: sortedByX(current)))
        return lines
    }

    // MARK: - Private

    /// Returns true when `candidate` is on the same visual line as `group`.
    private static func sameLine(_ group: [PopplerTextBox], candidate: PopplerTextBox) -> Bool {
        guard let last = group.last else { return true }

        // Y-centre proximity.
        let maxFontSize = max(last.fontSize, candidate.fontSize)
        let tolerance = maxFontSize * yToleranceRatio
        let yCentreLast = (last.boundingBox.top + last.boundingBox.bottom) / 2
        let yCentreCand = (candidate.boundingBox.top + candidate.boundingBox.bottom) / 2
        guard abs(yCentreLast - yCentreCand) <= tolerance else { return false }

        // Style guard: don't merge boxes with very different font sizes.
        // A heading at 16 pt and body text at 11 pt (ratio ≈ 1.45) should remain
        // separate elements even when they happen to share a baseline — merging
        // them fuses the heading into the body line and breaks heading detection.
        if last.fontSize > 0, candidate.fontSize > 0 {
            let ratio =
                max(last.fontSize, candidate.fontSize)
                / min(last.fontSize, candidate.fontSize)
            if ratio > 1.5 { return false }
        }

        return true
    }

    private static func sortedByX(_ boxes: [PopplerTextBox]) -> [PopplerTextBox] {
        boxes.sorted { $0.boundingBox.left < $1.boundingBox.left }
    }
}
