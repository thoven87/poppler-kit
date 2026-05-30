# Getting Started

Add PopplerKit to your project and extract text from a PDF in minutes.

## Requirements

| | Minimum | Notes |
|---|---|---|
| Swift | 6.0 | | 
| macOS *(deploy)* | 13 | Minimum OS **apps built with PopplerKit** can run on |
| macOS *(develop)* | 14.5 | Minimum OS to run Xcode 16 and **build** the package |
| Linux | Ubuntu 22.04 | poppler ≥ 22.02 |

> **Note:** If you develop on macOS 16 (Tahoe) or later, that is perfectly fine — you are
> building *with* a newer OS, not *targeting* it exclusively.  The `.macOS(.v15)` in
> `Package.swift` is the *deployment target*, meaning apps you ship can run on macOS 13+.

## Installation

### macOS

```bash
brew install pkg-config poppler
```

`pkg-config` is required — Swift Package Manager uses it to locate the
`poppler-cpp` headers and library flags via `pkg-config poppler-cpp`.  
Homebrew tracks the latest stable poppler release.

### Linux — build from source

PopplerKit requires poppler ≥ 26.05.0. Linux distributions do not yet ship this
version in their package managers, so you must build poppler from source.
Ubuntu 24.04 LTS provides all the required build-time dependencies.

```bash
# 1. Install build dependencies (Ubuntu 24.04+)
apt-get install -y build-essential cmake wget pkg-config \
  libfreetype-dev libfontconfig-dev libjpeg-dev libpng-dev libtiff-dev \
  libopenjp2-7-dev zlib1g-dev liblcms2-dev libnss3-dev libcairo2-dev xz-utils

# 2. Download and build poppler 26.05.0
cd /tmp
wget https://poppler.freedesktop.org/poppler-26.05.0.tar.xz
tar -xJf poppler-26.05.0.tar.xz

cmake -S poppler-26.05.0 -B poppler-build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DENABLE_BOOST=OFF -DENABLE_QT5=OFF -DENABLE_QT6=OFF \
  -DENABLE_GLIB=OFF -DENABLE_LIBCURL=OFF \
  -DENABLE_CPP=ON -DENABLE_UTILS=ON \
  -DENABLE_LIBOPENJPEG=openjpeg2

cmake --build poppler-build --parallel "$(nproc)"
cmake --install poppler-build
ldconfig

# 3. Verify
pkg-config --modversion poppler-cpp   # should print 26.05.0
```

> **Docker / Cloud Run:** Use `swift:6.3` (Ubuntu 24.04) as your base image.
> The CI workflows in this repository demonstrate the exact build steps.

### Swift Package Manager

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/thoven87/poppler-kit", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "PopplerKit",   package: "poppler-kit"),  // C++ in-process
        .product(name: "PopplerUtils", package: "poppler-kit"),  // CLI subprocess (optional)
    ]),
]
```

## Load a document

```swift
import PopplerKit

// From a file path
let doc = try PopplerDocument.load(from: URL(fileURLWithPath: "/path/to/document.pdf"))

// From memory (e.g. downloaded data)
let doc = try PopplerDocument.load(from: pdfData)

// Password-protected
let doc = try PopplerDocument.load(from: url, ownerPassword: "owner", userPassword: "user")
```

Throws ``PopplerError/documentLoadFailed`` if the file is missing, corrupt, or the password is
wrong.  Check ``PopplerDocument/isLocked`` to detect partially-open encrypted files.

## Decide: text or images?

Most PDFs have an embedded text layer; scanned documents do not.  Check before extraction:

```swift
if doc.hasExtractableText {
    // Use PopplerKit's text APIs (fast, no rasterisation)
    let text = try await doc.extractText()
} else {
    // Rasterise and send to OCR or a multimodal LLM
    for try await b64 in doc.rasterBase64Stream() {
        try await ollamaClient.generate(image: b64, prompt: "Extract all text.")
    }
}
```

## Stream text page-by-page

For large documents, stream results rather than loading everything at once:

```swift
for try await pageText in doc.textStream() {
    process(pageText)   // called once per non-empty page
}
```

The stream is cancellable — each step checks `Task.checkCancellation()`, so cancelling the enclosing `Task` or breaking from the loop halts iteration cleanly with no task leak.

## Next steps

- <doc:TextExtraction> — all text APIs and when to use each
- <doc:Rasterization> — rendering pipeline and LLM integration
- <doc:WorkingWithDocuments> — metadata, security, structure, saving
- <doc:TableExtraction> — coordinate-based table parsing
- <doc:DockerAndCloudRun> — deploying to containers and Cloud Run
