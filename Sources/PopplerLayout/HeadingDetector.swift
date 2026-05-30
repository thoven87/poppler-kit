import PopplerKit

// MARK: - FontStatistics
//
// Collects font-size frequencies across all lines of a document so that
// HeadingDetector can apply a "rarity boost": a line whose font size is
// used by fewer than `rarityThreshold` fraction of all lines receives a
// higher heading probability.

struct FontStatistics: Sendable {

    private let sizeCounts: [Double: Int]  // rounded font size → occurrence count
    private let totalLines: Int
    private let weightCounts: [Double: Int]  // font weight (bold ~= 700) → count
    private let bodySize: Double  // most-common (modal) font size

    init(allLines: [[LayoutTextLine]]) {
        var sc = [Double: Int]()
        var wc = [Double: Int]()
        var tot = 0
        for pageLines in allLines {
            for line in pageLines {
                let sz = (line.fontSize * 2).rounded() / 2  // 0.5-pt buckets
                sc[sz, default: 0] += 1
                // Crude weight signal: names containing "Bold" → weight ≈ 700
                let w: Double = (line.fontName?.contains(/(?i)bold/) ?? false) ? 700 : 400
                wc[w, default: 0] += 1
                tot += 1
            }
        }
        self.sizeCounts = sc
        self.weightCounts = wc
        self.totalLines = tot
        self.bodySize = sc.max(by: { $0.value < $1.value })?.key ?? 12
    }

    /// Boost [0, 0.5] added when the font size is larger than body and rare.
    func fontSizeRarityBoost(for line: LayoutTextLine) -> Double {
        guard totalLines > 0, line.fontSize > bodySize else { return 0 }
        let sz = (line.fontSize * 2).rounded() / 2
        let freq = Double(sizeCounts[sz] ?? 0) / Double(totalLines)
        // Rare (≤10% of lines) AND larger-than-body → max boost
        let rarity = max(0, 0.1 - freq) / 0.1  // 0…1
        return rarity * 0.5
    }

    /// Boost [0, 0.3] for bold text that is rare in the document.
    func fontWeightRarityBoost(for line: LayoutTextLine) -> Double {
        guard totalLines > 0 else { return 0 }
        let isBold = line.fontName?.contains(/(?i)bold/) ?? false
        guard isBold else { return 0 }
        let freq = Double(weightCounts[700] ?? 0) / Double(totalLines)
        let rarity = max(0, 0.3 - freq) / 0.3  // 0…1
        return rarity * 0.3
    }

    var dominantBodySize: Double { bodySize }
}

// MARK: - HeadingDetector

public enum HeadingDetector {

    /// Minimum combined probability required to classify a line as a heading.
    static let headingThreshold: Double = 0.6

    // MARK: - Public

    /// For each page's lines, return a parallel Bool array: `true` = heading.
    public static func detectHeadings(
        in pageLines: [[LayoutTextLine]]
    ) -> [[Bool]] {
        let stats = FontStatistics(allLines: pageLines)
        return pageLines.map { lines in
            classifyPage(lines, stats: stats)
        }
    }

    /// Assign heading levels 1…6 to lines already classified as headings.
    /// Returns a dictionary mapping rounded font size → level.
    public static func headingLevels(
        in pageLines: [[LayoutTextLine]],
        isHeading: [[Bool]]
    ) -> [Double: Int] {
        // Collect all unique heading font sizes, sorted descending → level 1 first
        var headingSizes = Set<Double>()
        for (pi, lines) in pageLines.enumerated() {
            for (li, line) in lines.enumerated() where isHeading[pi][li] {
                headingSizes.insert((line.fontSize * 2).rounded() / 2)
            }
        }
        let sortedSizes = headingSizes.sorted(by: >)  // largest = level 1
        var sizeToLevel = [Double: Int]()
        for (idx, sz) in sortedSizes.enumerated() {
            sizeToLevel[sz] = min(idx + 1, 6)
        }
        return sizeToLevel
    }

    // MARK: - Private

    private static func classifyPage(_ lines: [LayoutTextLine], stats: FontStatistics) -> [Bool] {
        lines.enumerated().map { (idx, line) in
            var probability = baseProbability(line, stats: stats)
            probability += stats.fontSizeRarityBoost(for: line)
            probability += stats.fontWeightRarityBoost(for: line)
            // Short single-line text with elevated styling → extra boost
            if line.boxes.count == 1, line.text.count < 80 {
                probability += 0.05
            }
            return probability >= headingThreshold
        }
    }

    /// Base probability that a line is a heading (0…0.65).
    ///
    /// The cap is 0.65 (above the 0.6 threshold) so that a line whose font size
    /// is dramatically larger than body text — e.g. a 32 pt title in a 10 pt body
    /// (ratio 2.2) — is classified as a heading on font size alone, without
    /// requiring additional rarity or bold signals.  The rarity boost is calibrated
    /// for long documents (≥ 20 lines) and can under-fire on short ones.
    private static func baseProbability(_ line: LayoutTextLine, stats: FontStatistics) -> Double {
        guard line.fontSize > stats.dominantBodySize * 1.05 else { return 0 }
        // Linearly map [body*1.05 … body*2.375] → [0.1 … 0.65]
        let ratio = (line.fontSize - stats.dominantBodySize) / stats.dominantBodySize
        return min(0.65, 0.1 + ratio * 0.4)
    }
}
