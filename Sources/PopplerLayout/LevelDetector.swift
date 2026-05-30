import PopplerKit

// MARK: - LevelDetector
//
// Assigns nesting levels to list items by comparing each item's left-edge X
// position against the page's dominant body-text left margin.
//
// Algorithm:
//   1. Compute the body left margin = median of paragraph/heading left edges.
//   2. Walk the element list, tracking a stack of (leftX, level) pairs.
//   3. For each list item:
//      a. If left ≈ stack-top left → same level as stack top.
//      b. If left > stack-top left + indent threshold → push a deeper level.
//      c. If left < stack-top left − indent threshold → pop until a matching
//         (or shallower) level is found.
//   4. Reset the stack whenever a non-list element is encountered (headings
//      break list nesting; paragraphs may or may not, depending on indentation).

public enum LevelDetector {

    /// Minimum x-offset (pt) from the previous level's left edge to count
    /// as a new, deeper nesting level.
    public static let indentThreshold: Double = 12.0

    // MARK: - Public

    /// Assign nesting levels to `.listItem` elements.
    ///
    /// - Parameters:
    ///   - elements: The assembled element list for one page.
    ///   - bodyLeftMargin: The dominant left margin of body text on the page.
    ///     Pass `nil` to auto-compute from `elements`.
    /// - Returns: A new array with `.listItem` elements updated to carry the
    ///   correct `nestingLevel`.
    public static func detectNesting(
        _ elements: [PopplerLayoutElement],
        bodyLeftMargin: Double? = nil
    ) -> [PopplerLayoutElement] {
        guard !elements.isEmpty else { return elements }

        let bodyLeft = bodyLeftMargin ?? computeBodyLeft(elements)

        // Stack of (leftX, nestingLevel) — top of stack is innermost level.
        var stack: [(leftX: Double, level: Int)] = []
        var result = [PopplerLayoutElement]()
        result.reserveCapacity(elements.count)

        for element in elements {
            guard case .listItem(let label, let text, let bb, _) = element else {
                // Non-list element: reset the nesting stack.
                if case .paragraph = element { /* paragraphs can be list content — keep stack */
                } else {
                    stack.removeAll()
                }
                result.append(element)
                continue
            }

            let left = bb.left
            let level = resolveLevel(left: left, bodyLeft: bodyLeft, stack: &stack)
            result.append(.listItem(label: label, text: text, boundingBox: bb, nestingLevel: level))
        }
        return result
    }

    // MARK: - Private

    /// Auto-compute the dominant left margin from paragraph and heading left edges.
    static func computeBodyLeft(_ elements: [PopplerLayoutElement]) -> Double {
        let lefts: [Double] = elements.compactMap { el in
            switch el {
            case .paragraph(_, let bb): return bb.left
            case .heading(_, _, let bb, _): return bb.left
            default: return nil
            }
        }
        guard !lefts.isEmpty else { return 0 }
        // Use median to avoid skew from indented code blocks or captions.
        let sorted = lefts.sorted()
        return sorted[sorted.count / 2]
    }

    /// Resolve the nesting level for a list item at `left`, updating `stack` in place.
    static func resolveLevel(
        left: Double,
        bodyLeft: Double,
        stack: inout [(leftX: Double, level: Int)]
    ) -> Int {
        // Pop levels that are more indented than the current item.
        while let top = stack.last, left < top.leftX - indentThreshold {
            stack.removeLast()
        }

        if let top = stack.last {
            if abs(left - top.leftX) <= indentThreshold {
                // Same indentation → same level as top-of-stack.
                return top.level
            } else {
                // Deeper indentation → push a new level.
                let newLevel = top.level + 1
                stack.append((leftX: left, level: newLevel))
                return newLevel
            }
        } else {
            // Empty stack: first list item on the page.
            // Level 1 if near body margin, level 2+ if already indented.
            let indentation = left - bodyLeft
            let level = indentation > indentThreshold * 2 ? 2 : 1
            stack.append((leftX: left, level: level))
            return level
        }
    }
}
