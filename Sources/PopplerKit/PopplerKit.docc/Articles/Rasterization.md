# Rasterization

Render PDF pages to images for OCR, LLM inference, previews, and archival.

## When to rasterise

```swift
if doc.hasExtractableText {
    // Fast path: in-process text extraction
    let text = try await doc.extractText()
    // … feed to an LLM or search index
} else {
    // Slow path: rasterise → OCR or multimodal model
    for try await b64 in doc.rasterBase64Stream() {
        try await llm.analyse(image: b64)
    }
}
```

`hasExtractableText` samples the first five pages; it returns `true` as soon as any page yields
more than 20 non-whitespace characters.

## Streaming pages (recommended)

`rasterStream` yields each page as encoded `Data` as soon as it is rendered, without waiting for
the whole document:

```swift
for try await imageData in doc.rasterStream(xres: 150, yres: 150, format: .png) {
    try imageData.write(to: outputURL)
}

// With a page range
for try await imageData in doc.rasterStream(
    xres: 300,
    format: .jpeg,
    firstPage: 0,
    lastPage: 4
) {
    upload(imageData)
}
```

The stream is fully cancellable.

## Base64 for LLM pipelines

`rasterBase64Stream` is the primary entry point for multimodal LLM inference:

```swift
for try await b64 in doc.rasterBase64Stream(xres: 150) {
    let body: [String: Any] = [
        "model":  "medgemma:4b-it",
        "images": [b64],
        "prompt": "Extract all structured data from this document.",
        "stream": false,
    ]
    let response = try await ollamaClient.post("/api/generate", body: body)
}
```

## Collect all pages

For small documents where memory is not a concern:

```swift
let pages: [Data]   = try await doc.rasterize(xres: 300, format: .png)
let b64s:  [String] = try await doc.rasterizeToBase64(format: .jpeg)
```

## Resolution guidance

| Use case | `xres` / `yres` | File size |
|---|---|---|
| Quick preview | 72 DPI | Very small |
| LLM inference | 150 DPI | Small |
| OCR (standard) | 300 DPI | Medium |
| Archival / print | 600 DPI | Large |

## Low-level: raw pixel buffer

Use ``PopplerRenderer`` directly when you need the raw pixel data (e.g. for custom encoding,
`CoreImage` processing, or `vImage`):

```swift
let renderer = PopplerRenderer()
renderer.setAntialiasing(true)
renderer.setTextAntialiasing(true)

let page = try doc.page(at: 0)

// Raw pixel buffer
if let image = renderer.render(page: page, xres: 150, yres: 150) {
    print("\(image.width) × \(image.height) px, format: \(image.format)")
    // image.data is Data with raw RGB/ARGB bytes
}

// Encoded PNG/JPEG directly
if let png = renderer.renderToData(page: page, xres: 150, format: .png) {
    // ready-to-use PNG Data
}
```

## Page orientation

Before rendering, check the page orientation so you can rotate your canvas if needed:

```swift
let page = try doc.page(at: 0)
switch page.orientation {
case .portrait:   break                   // standard — no rotation
case .landscape:  rotateCanvas(by: 90)    // rotate 90° CW
case .seascape:   rotateCanvas(by: -90)   // rotate 90° CCW
case .upsideDown: rotateCanvas(by: 180)
}
```

## Page boxes

The default rendering uses the **crop box** (the visible area in PDF viewers).
Access other boxes when needed:

```swift
let page = try doc.page(at: 0)

page.cropBox   // viewer display area (default for width/height)
page.mediaBox  // full physical sheet (may be larger than cropBox)
page.bleedBox  // print bleed region
page.trimBox   // final cut size
page.artBox    // intended artwork extent

// Or access any box programmatically
let rect = page.pageRect(.bleed)
```
