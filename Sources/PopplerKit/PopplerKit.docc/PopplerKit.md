# ``PopplerKit``

Swift 6 in-process PDF library built on `libpoppler-cpp`.

## Overview

PopplerKit calls the Poppler C++ API directly — no subprocess spawning, no `PATH` dependencies, no
per-call temp files.  It ships alongside `PopplerUtils`, a subprocess wrapper for the `poppler-utils`
CLI tools that provides capabilities outside `libpoppler-cpp` (split, merge, SVG export, signing).

```swift
let doc  = try PopplerDocument.load(from: url)
let text = try await doc.extractText()          // streaming text pipeline
let b64  = try await doc.rasterizeToBase64()    // LLM-ready page images
```

## Topics

### Guides

- <doc:GettingStarted>
- <doc:TextExtraction>
- <doc:Rasterization>
- <doc:WorkingWithDocuments>
- <doc:TableExtraction>
- <doc:Concurrency>
- <doc:DockerAndCloudRun>

### Loading Documents

- ``PopplerDocument``
- ``PopplerError``

### Pages

- ``PopplerPage``
- ``PopplerTextBox``
- ``PopplerTextLayout``
- ``PDFTable``

### Rendering

- ``PopplerRenderer``
- ``PopplerImage``
- ``PopplerImageFormat``
- ``PopplerRasterFormat``

### Document Structure

- ``PopplerTOCItem``
- ``PopplerEmbeddedFile``
- ``PopplerFontInfo``
- ``PopplerDestination``
- ``PopplerPageTransition``

### Geometry & Coordinates

- ``PopplerRect``
- ``PopplerPageBox``
- ``PopplerPageOrientation``

### Metadata & Security

- ``PopplerPermissions``
- ``PopplerFormType``
- ``PopplerPageLayout``
- ``PopplerPageMode``

### Fonts & Text

- ``PopplerFontType``
- ``PopplerWritingMode``
- ``PopplerDestinationType``
- ``PopplerTransitionAlignment``
- ``PopplerTransitionDirection``
- ``PopplerPageTransitionType``
