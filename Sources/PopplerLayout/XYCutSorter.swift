import PopplerKit

// MARK: - XYCutSorter
//
// XY-Cut++ reading-order algorithm (arXiv:2504.10258).
//
// Operates on arrays of bounding boxes via index, so the caller's element type
// is unchanged.  Phase summary:
//   1. Pre-mask: wide elements that span multiple columns (headers, titles)
//   2. Density ratio → preferred split axis
//   3. Recursive XY/YX-Cut on largest whitespace gap
//   4. Stitch cross-layout elements back in by Y position

/// Sorts `boxes` into reading order and returns the corresponding sorted indices.
public enum XYCutSorter {

    // MARK: - Tuning constants

    /// Cross-layout width threshold: element must be ≥ beta × maxWidth to be a candidate.
    /// Default 2.0 effectively disables cross-layout masking; set 0.7 to enable for
    /// documents with page-spanning titles/headers.
    static let defaultBeta: Double = 0.7
    static let defaultDensityThreshold: Double = 0.9
    /// Minimum horizontal overlap ratio (relative to the smaller box) to count as overlapping.
    static let overlapThreshold: Double = 0.1
    static let minOverlapCount: Int = 2
    /// Smallest whitespace gap that warrants a cut.
    static let minGapThreshold: Double = 5.0
    /// Elements narrower than this fraction of the region width are ignored when
    /// finding column gaps (avoids page numbers bridging a column split).
    static let narrowElementRatio: Double = 0.1

    // MARK: - Public entry point

    /// Sort bounding boxes into reading order; return re-ordered indices.
    public static func sortedIndices(of boxes: [PopplerRect]) -> [Int] {
        guard boxes.count > 1 else { return Array(boxes.indices) }
        let indices = Array(boxes.indices)
        return sortIndices(
            indices, boxes: boxes,
            beta: defaultBeta,
            densityThreshold: defaultDensityThreshold)
    }

    // MARK: - Internal phases

    static func sortIndices(
        _ indices: [Int],
        boxes: [PopplerRect],
        beta: Double,
        densityThreshold: Double
    ) -> [Int] {
        guard indices.count > 1 else { return indices }

        // Phase 1 — cross-layout detection
        let crossIdx = crossLayoutIndices(from: indices, boxes: boxes, beta: beta)
        let mainIdx = indices.filter { !crossIdx.contains($0) }

        if mainIdx.isEmpty { return sortByYThenX(indices, boxes: boxes) }

        // Phase 2 — density ratio
        let density = densityRatio(of: mainIdx, boxes: boxes)
        let preferH = density > densityThreshold

        // Phase 3 — recursive segmentation
        let sortedMain = recursiveSegment(mainIdx, boxes: boxes, preferH: preferH)

        // Phase 4 — merge cross-layout back in
        return mergeBack(main: sortedMain, cross: crossIdx, boxes: boxes)
    }

    // MARK: Phase 1 — cross-layout masking

    static func crossLayoutIndices(from indices: [Int], boxes: [PopplerRect], beta: Double) -> Set<
        Int
    > {
        guard indices.count >= 3 else { return [] }
        let maxW = indices.map { boxes[$0].width }.max() ?? 0
        let threshold = beta * maxW
        var result = Set<Int>()
        for i in indices where boxes[i].width >= threshold {
            if overlapCount(for: i, in: indices, boxes: boxes) >= minOverlapCount {
                result.insert(i)
            }
        }
        return result
    }

    private static func overlapCount(for idx: Int, in indices: [Int], boxes: [PopplerRect]) -> Int {
        let box = boxes[idx]
        var count = 0
        for j in indices where j != idx {
            if horizontalOverlapRatio(box, boxes[j]) >= overlapThreshold {
                count += 1
                if count >= minOverlapCount { return count }
            }
        }
        return count
    }

    static func horizontalOverlapRatio(_ a: PopplerRect, _ b: PopplerRect) -> Double {
        let ol = max(a.left, b.left)
        let or_ = min(a.right, b.right)
        let overlap = max(0, or_ - ol)
        guard overlap > 0 else { return 0 }
        let smaller = min(a.width, b.width)
        return smaller > 0 ? overlap / smaller : 0
    }

    // MARK: Phase 2 — density ratio

    static func densityRatio(of indices: [Int], boxes: [PopplerRect]) -> Double {
        guard let region = boundingRegion(of: indices, boxes: boxes) else { return 1 }
        let regionArea = region.width * region.height
        guard regionArea > 0 else { return 1 }
        let contentArea = indices.reduce(0.0) { $0 + boxes[$1].width * boxes[$1].height }
        return min(1, contentArea / regionArea)
    }

    static func boundingRegion(of indices: [Int], boxes: [PopplerRect]) -> PopplerRect? {
        guard !indices.isEmpty else { return nil }
        var minL = Double.infinity
        var maxR = -Double.infinity
        var minB = Double.infinity
        var maxT = -Double.infinity
        for i in indices {
            let b = boxes[i]
            minL = min(minL, b.left)
            maxR = max(maxR, b.right)
            minB = min(minB, b.bottom)
            maxT = max(maxT, b.top)
        }
        guard maxR > minL, maxT > minB else { return nil }
        return PopplerRect(left: minL, top: maxT, right: maxR, bottom: minB)
    }

    // MARK: Phase 3 — recursive XY/YX segmentation

    private struct Cut {
        let position: Double
        let gap: Double
    }

    static func recursiveSegment(_ indices: [Int], boxes: [PopplerRect], preferH: Bool) -> [Int] {
        guard indices.count > 1 else { return indices }

        let hCut = bestHorizontalCut(indices, boxes: boxes)
        let vCut = bestVerticalCut(indices, boxes: boxes)

        let hasH = hCut.gap >= minGapThreshold
        let hasV = vCut.gap >= minGapThreshold

        var useH: Bool
        if hasH && hasV {
            useH = hCut.gap > vCut.gap
        } else if hasH {
            useH = true
        } else if hasV {
            useH = false
        } else {
            return sortByYThenX(indices, boxes: boxes)
        }

        // Row-based layout guard (TOC / index pages):
        // If we're about to do a vertical cut, check whether the two halves are
        // actually horizontally-paired rows (e.g. "Chapter 1 .... 5") rather than
        // independent columns.  Key signals: small element heights (< 45 pt) and a
        // large column gutter (>= 80 pt).  When detected, override to a horizontal
        // cut so entries are read row-by-row instead of column-by-column.
        if !useH, hasV {
            let leftI = indices.filter { (boxes[$0].left + boxes[$0].right) / 2 < vCut.position }
            let rightI = indices.filter { (boxes[$0].left + boxes[$0].right) / 2 >= vCut.position }
            if isRowBasedLayout(
                left: leftI, right: rightI, boxes: boxes,
                verticalGap: vCut.gap, horizontalGap: hCut.gap)
            {
                if hCut.gap >= 1.5 {
                    useH = true
                } else {
                    return sortByYThenX(indices, boxes: boxes)
                }
            }
        }

        let groups: [[Int]]
        if useH {
            groups = splitHorizontal(indices, at: hCut.position, boxes: boxes)
        } else {
            groups = splitVertical(indices, at: vCut.position, boxes: boxes)
        }
        guard groups.count > 1 else { return sortByYThenX(indices, boxes: boxes) }

        return groups.flatMap { recursiveSegment($0, boxes: boxes, preferH: preferH) }
    }

    /// Two rects share a horizontal band when their Y-ranges overlap by ≥ 50% of
    /// the shorter element’s height.  Works with both y-UP and y-DOWN conventions.
    static func isVerticallyAligned(_ a: PopplerRect, _ b: PopplerRect) -> Bool {
        let aLo = min(a.top, a.bottom)
        let aHi = max(a.top, a.bottom)
        let bLo = min(b.top, b.bottom)
        let bHi = max(b.top, b.bottom)
        let overlap = max(0, min(aHi, bHi) - max(aLo, bLo))
        let minHeight = min(aHi - aLo, bHi - bLo)
        return minHeight > 0 && overlap / minHeight >= 0.5
    }

    /// Detects TOC / index layouts: paired left+right elements of small height
    /// separated by a large horizontal gutter.
    ///
    /// - Parameters:
    ///   - verticalGap:   gap of the pending vertical cut (column separator width).
    ///   - horizontalGap: gap of the best horizontal cut (row spacing).
    static func isRowBasedLayout(
        left: [Int], right: [Int], boxes: [PopplerRect],
        verticalGap: Double, horizontalGap: Double
    ) -> Bool {
        guard !left.isEmpty, !right.isEmpty else { return false }

        var alignedCount = 0
        var totalHeight = 0.0
        for li in left {
            for ri in right {
                if isVerticallyAligned(boxes[li], boxes[ri]) {
                    alignedCount += 1
                    totalHeight += abs(boxes[li].top - boxes[li].bottom)
                    break
                }
            }
        }
        guard alignedCount >= 2 else { return false }

        // Require ≥3 aligned pairs OR a very large gutter (dominant signal alone).
        let hasLargeGutter =
            verticalGap >= 80.0
            && verticalGap >= 8.0 * max(1.0, horizontalGap)
        guard alignedCount >= 3 || hasLargeGutter else { return false }

        let avgHeight = totalHeight / Double(alignedCount)
        let ratio = Double(alignedCount) / Double(left.count)
        return ratio >= 0.5 && avgHeight < 45.0
    }

    // MARK: — Horizontal cut (splits top from bottom)

    private static func bestHorizontalCut(_ indices: [Int], boxes: [PopplerRect]) -> Cut {
        // Sort top→bottom (higher `top` value first in PDF coords)
        let sorted = indices.sorted { boxes[$0].top > boxes[$1].top }
        var best = Cut(position: 0, gap: 0)
        var prevBottom: Double? = nil
        for i in sorted {
            let b = boxes[i]
            if let pb = prevBottom, pb > b.top {
                let gap = pb - b.top
                if gap > best.gap {
                    best = Cut(position: (pb + b.top) / 2, gap: gap)
                }
            }
            prevBottom = prevBottom.map { min($0, b.bottom) } ?? b.bottom
        }
        return best
    }

    // MARK: — Vertical cut (splits left column from right)

    private static func bestVerticalCut(_ indices: [Int], boxes: [PopplerRect]) -> Cut {
        let cut = edgeBasedVerticalCut(indices, boxes: boxes)
        if cut.gap >= minGapThreshold { return cut }

        // Retry ignoring narrow outliers (page numbers etc.)
        guard indices.count >= 3,
            let region = boundingRegion(of: indices, boxes: boxes)
        else { return cut }
        let narrowThreshold = region.width * narrowElementRatio
        let filtered = indices.filter { boxes[$0].width >= narrowThreshold }
        guard filtered.count >= 2, filtered.count < indices.count else { return cut }
        let filteredCut = edgeBasedVerticalCut(filtered, boxes: boxes)
        return filteredCut.gap > cut.gap ? filteredCut : cut
    }

    private static func edgeBasedVerticalCut(_ indices: [Int], boxes: [PopplerRect]) -> Cut {
        let sorted = indices.sorted {
            boxes[$0].left != boxes[$1].left
                ? boxes[$0].left < boxes[$1].left
                : boxes[$0].right < boxes[$1].right
        }
        var best = Cut(position: 0, gap: 0)
        var prevRight: Double? = nil
        for i in sorted {
            let b = boxes[i]
            if let pr = prevRight, b.left > pr {
                let gap = b.left - pr
                if gap > best.gap {
                    best = Cut(position: (pr + b.left) / 2, gap: gap)
                }
            }
            prevRight = prevRight.map { max($0, b.right) } ?? b.right
        }
        return best
    }

    // MARK: — Splitting helpers

    private static func splitHorizontal(_ indices: [Int], at cutY: Double, boxes: [PopplerRect])
        -> [[Int]]
    {
        var above = [Int]()
        var below = [Int]()
        for i in indices {
            let centerY = (boxes[i].top + boxes[i].bottom) / 2
            if centerY > cutY { above.append(i) } else { below.append(i) }
        }
        return [above, below].filter { !$0.isEmpty }
    }

    private static func splitVertical(_ indices: [Int], at cutX: Double, boxes: [PopplerRect])
        -> [[Int]]
    {
        var left = [Int]()
        var right = [Int]()
        for i in indices {
            let centerX = (boxes[i].left + boxes[i].right) / 2
            if centerX < cutX { left.append(i) } else { right.append(i) }
        }
        return [left, right].filter { !$0.isEmpty }
    }

    // MARK: Phase 4 — merge cross-layout elements back in

    private static func mergeBack(main: [Int], cross: Set<Int>, boxes: [PopplerRect]) -> [Int] {
        guard !cross.isEmpty else { return main }
        guard !main.isEmpty else { return sortByYThenX(Array(cross), boxes: boxes) }

        let sortedCross = sortByYThenX(Array(cross), boxes: boxes)
        var result = [Int]()
        result.reserveCapacity(main.count + sortedCross.count)

        var mi = 0
        var ci = 0
        while mi < main.count || ci < sortedCross.count {
            if ci >= sortedCross.count {
                result.append(main[mi])
                mi += 1
            } else if mi >= main.count {
                result.append(sortedCross[ci])
                ci += 1
            } else {
                // Higher `top` value → higher on page → comes first
                if boxes[sortedCross[ci]].top >= boxes[main[mi]].top {
                    result.append(sortedCross[ci])
                    ci += 1
                } else {
                    result.append(main[mi])
                    mi += 1
                }
            }
        }
        return result
    }

    // MARK: — Utility

    /// Sort indices top→bottom, then left→right.
    static func sortByYThenX(_ indices: [Int], boxes: [PopplerRect]) -> [Int] {
        indices.sorted {
            let a = boxes[$0]
            let b = boxes[$1]
            if a.top != b.top { return a.top > b.top }  // higher top first
            return a.left < b.left  // leftmost first
        }
    }
}

// MARK: - PopplerRect geometry helpers

extension PopplerRect {
    fileprivate var width: Double { right - left }
    fileprivate var height: Double { top - bottom }  // positive when top > bottom (normal PDF)
}
