# PopplerKit

Swift 6 PDF library for macOS and Linux, built on [Poppler](https://poppler.freedesktop.org/).

[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)](https://swift.org/server)

## Products

| Product | API | System dependency |
|---|---|---|
| **`PopplerKit`** | In-process C++ binding — text, metadata, rendering, table extraction | `libpoppler-cpp` |
| **`PopplerUtils`** | Subprocess wrappers for `poppler-utils` CLI — split, merge, SVG, signing | `poppler-utils` |

## Install

```swift
// Package.swift
.package(url: "https://github.com/thoven87/poppler-kit", from: "1.0.0")
```

```bash
brew install pkg-config poppler          # macOS (develop on macOS 14.5+, target macOS 13+)
apt-get install libpoppler-cpp-dev       # Linux / Docker (PopplerKit)
apt-get install poppler-utils            # Linux / Docker (PopplerUtils)
```

## Quick start

```swift
import PopplerKit

let doc = try PopplerDocument.load(from: url)

// Text-layer PDF → stream text
if doc.hasExtractableText {
    for try await pageText in doc.textStream() { process(pageText) }
}

// Scanned PDF → stream base64 images for LLM inference
else {
    for try await b64 in doc.rasterBase64Stream(xres: 150) {
        try await llm.analyse(image: b64)
    }
}
```

## Documentation

Full API reference and guides are in the **DocC documentation**:

```bash
swift package generate-documentation --target PopplerKit
swift package generate-documentation --target PopplerUtils
```

### Guides

- **Getting Started** — installation, loading, first extraction
- **Text Extraction** — `textStream`, `textBoxes`, region extraction, search
- **Rasterization** — rendering pipeline, LLM integration, resolution guide
- **Working with Documents** — metadata, security, permissions, structure, saving
- **Table Extraction** — `PDFTable`, keyword selection, multi-page tables
- **Docker and Cloud Run** — container setup, Cloud Run config, Ubuntu compatibility
