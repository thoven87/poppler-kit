# ``PopplerUtils``

Subprocess wrappers for the `poppler-utils` CLI tools.

## Overview

`PopplerUtils` covers operations that lie outside `libpoppler-cpp` — the stable public C++ API that
``PopplerKit`` is built on.  These tools need `poppler-utils` installed on the host system but have
zero C++ interoperability requirements.

| When to choose `PopplerUtils` | When to choose `PopplerKit` |
|---|---|
| Split or merge PDFs | Extract text or metadata |
| Render to SVG, EPS, PostScript | Render to PNG / JPEG |
| Extract source image objects | Rasterise whole pages |
| Sign or verify digital signatures | Access font/TOC/bookmark data |
| Only `poppler-utils` is installed | `libpoppler-cpp` is available |

```swift
// Merge three PDFs
try await PopplerUtils.mergePDFs([invoiceURL, appendixURL, coverURL], to: outputURL)

// Export page 1 as SVG
try await PopplerUtils.convertToSVG(pdfURL: url, outputBase: svgDir.appendingPathComponent("page"))

// Sign with an NSS certificate
try await PopplerUtils.sign(
    pdfURL: unsignedURL, outputURL: signedURL,
    certificateNick: "MySigningCert", nssCertDB: nssDir
)
```

See <doc:DockerAndCloudRun> for how to install the required system packages.

## Topics

### Attaching & Detaching Files
- ``PopplerUtils/attach(file:to:output:replace:)``
- ``PopplerUtils/extractAttachment(number:from:to:)``
- ``PopplerUtils/extractAllAttachments(from:into:)``

### Fonts & Metadata
- ``PopplerUtils/listFonts(in:firstPage:lastPage:)``
- ``PopplerUtils/info(pdfURL:ownerPassword:userPassword:)``
- ``PDFFontEntry``
- ``PDFInfo``

### Image Extraction
- ``PopplerUtils/extractEmbeddedImages(from:into:format:firstPage:lastPage:)``
- ``PopplerUtils/EmbeddedImageFormat``

### Splitting & Merging
- ``PopplerUtils/separatePages(from:into:firstPage:lastPage:)``
- ``PopplerUtils/mergePDFs(_:to:)``

### Digital Signatures
- ``PopplerUtils/listSignatures(in:nssCertDB:nocert:)``
- ``PopplerUtils/sign(pdfURL:outputURL:certificateNick:nssCertDB:nssPassword:fieldName:reason:digest:etsi:)``
- ``PopplerUtils/SignatureInfo``

### Vector & Raster Rendering
- ``PopplerUtils/convertToSVG(pdfURL:outputBase:firstPage:lastPage:)``
- ``PopplerUtils/convertToPostScript(pdfURL:outputURL:firstPage:lastPage:level3:)``
- ``PopplerUtils/convertToEPS(pdfURL:outputURL:page:)``
- ``PopplerUtils/convertToPDF(pdfURL:outputURL:firstPage:lastPage:)``
- ``PopplerUtils/renderPagesCairo(pdfURL:outputBase:format:resolution:grayscale:transparent:firstPage:lastPage:)``
- ``PopplerUtils/renderPages(pdfURL:into:format:resolution:grayscale:firstPage:lastPage:scaleToMaxPixels:)``
- ``PopplerUtils/exportToPostScript(pdfURL:outputURL:level:firstPage:lastPage:eps:)``
- ``PopplerUtils/RasterFormat``
- ``PopplerUtils/PostScriptLevel``

### HTML Conversion
- ``PopplerUtils/convertToHTML(pdfURL:outputDirectory:firstPage:lastPage:singleFile:ignoreImages:zoom:noFrames:)``

### Text Extraction
- ``PopplerUtils/extractText(from:layout:firstPage:lastPage:noPageBreaks:ownerPassword:userPassword:)``
- ``PopplerUtils/extractText(from:to:layout:firstPage:lastPage:)``
- ``PopplerUtils/TextLayout``
