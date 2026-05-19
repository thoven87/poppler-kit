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
# macOS — both are required: pkg-config is used by SPM to resolve poppler-cpp headers
brew install pkg-config poppler

# Linux / Docker — poppler 26.05.0 must be built from source (Ubuntu 24.04 provides deps)
# See the DocC GettingStarted guide or the CI workflows for the exact cmake invocation.
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
