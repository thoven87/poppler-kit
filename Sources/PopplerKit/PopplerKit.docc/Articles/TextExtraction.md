# Text Extraction

Choose the right API for your document size, layout, and precision needs.

## API overview

| API | Granularity | Best for |
|---|---|---|
| ``PopplerDocument/textStream(layout:firstPage:lastPage:)`` | Per page, streamed | Large documents, pipelines |
| ``PopplerDocument/extractText(layout:firstPage:lastPage:)`` | Whole document | Small documents, quick reads |
| ``PopplerPage/text(layout:)`` | Single page | Per-page processing |
| ``PopplerPage/textBoxes()`` | Per word / glyph run | Layout analysis, table detection |
| ``PopplerPage/text(in:layout:)`` | Rectangular region | Targeted field extraction |
| ``PopplerPage/search(for:caseSensitive:)`` | Match bounding boxes | Find-in-document |

## Streaming (recommended for large files)

`textStream` yields one string per non-empty page without loading all pages into memory at once.
Blank and image-only pages are silently skipped.

```swift
for try await pageText in doc.textStream() {
    await database.insert(pageText)
}

// With options
for try await pageText in doc.textStream(
    layout: .physical,    // preserve columns
    firstPage: 3,         // 0-based
    lastPage: 10
) {
    process(pageText)
}
```

## Layout options

``PopplerTextLayout`` controls how positional information is used when assembling the text string.

| Value | `pdftotext` flag | Use when |
|---|---|---|
| `.natural` *(default)* | *(default)* | Prose, mixed layouts — logical reading order |
| `.physical` | `-layout` | Multi-column documents, tables, fixed-format reports |
| `.rawOrder` | `-raw` | Content-stream order; fastest, may be non-visual |

## Collect all text

```swift
// Whole document
let text = try await doc.extractText()

// Specific pages and layout
let section = try await doc.extractText(layout: .physical, firstPage: 5, lastPage: 15)
```

## Per-page text

```swift
let page = try doc.page(at: 0)          // 0-based
let text = page.text()                   // natural layout
let cols = page.text(layout: .physical)  // column-preserving
```

## Word-level bounding boxes

`textBoxes()` returns every word or glyph run with its exact position in PDF points.
Use this when spatial layout matters — table reconstruction, form reading, coordinate-aware search.

```swift
let boxes = page.textBoxes()

for box in boxes {
    print(box.text)           // word text
    print(box.boundingBox)    // PopplerRect in PDF points
    print(box.fontName)       // String? — font name if available
    print(box.fontSize)       // Double
    print(box.writingMode)    // .horizontal / .vertical (CJK)
    print(box.charBBoxes)     // [PopplerRect] — per-glyph bounding boxes
}

// Normalise to 0…1 fractions using the page's crop box
let w = page.width, h = page.height
for box in boxes {
    let normX = box.boundingBox.left / w
    let normY = box.boundingBox.top  / h
}
```

## Region extraction

Extract text from a specific rectangle (e.g. a table cell or header zone):

```swift
// First find the region from textBoxes(), then extract its text
let headerBoxes = page.textBoxes().filter { $0.boundingBox.top < 60 }
if let headerRegion = headerBoxes.first?.boundingBox {
    let headerText = page.text(in: headerRegion, layout: .physical)
}

// Or construct a region directly (PDF points, origin bottom-left)
let region = PopplerRect(left: 0, top: 700, right: 612, bottom: 792)
let text = page.text(in: region)
```

## Search

Find all occurrences of a string and get their bounding boxes:

```swift
let hits = page.search(for: "Invoice No.", caseSensitive: false)

for rect in hits {
    // rect is in the same coordinate space as textBoxes().boundingBox
    let fieldValue = page.text(in: PopplerRect(
        left:   rect.right,
        top:    rect.top - 5,
        right:  rect.right + 150,
        bottom: rect.bottom + 5
    ))
    print("Invoice number: \(fieldValue)")
}
```

## Page labels

Some documents use logical labels (`"i"`, `"ii"`, `"1"`, `"A-1"`) that differ from the 0-based index:

```swift
// Find page by its printed number
let page = try doc.page(labeled: "A-1")

// Display the correct number to the user
for try await page in doc.pages {
    let displayNumber = page.label ?? String(page.mediaBox.width > 0 ? "?" : "-")
}
```
