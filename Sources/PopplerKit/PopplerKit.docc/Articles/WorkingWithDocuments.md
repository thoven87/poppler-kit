# Working with Documents

Access metadata, security settings, document structure, and save modified files.

## Metadata

All standard PDF info-dictionary fields are available as optional properties (returning `nil` when
not set):

```swift
let doc = try PopplerDocument.load(from: url)

print(doc.title)            // String?
print(doc.author)           // String?
print(doc.subject)          // String?
print(doc.keywords)         // String?
print(doc.creator)          // String? — application that created the source
print(doc.producer)         // String? — PDF writer
print(doc.creationDate)     // Date?
print(doc.modificationDate) // Date?
print(doc.pdfVersion)       // (major: Int, minor: Int)
print(doc.pageCount)        // Int
```

### XMP metadata

```swift
if let xmp = doc.xmpMetadata {
    // Raw XML packet — parse with XMLDocument or a dedicated XMP library
}
```

### Document identity

```swift
if let id = doc.pdfID {
    print("Permanent: \(id.permanent)")  // never changes after creation
    print("Update:    \(id.update)")     // changes on each save
}
```

### Custom info keys

```swift
let keys = doc.infoKeys()  // ["Title", "Author", "Company", ...]
if let company = doc.infoValue(forKey: "Company") {
    print("Produced by: \(company)")
}
```

## Security

```swift
doc.isEncrypted   // Bool — any encryption present
doc.isLocked      // Bool — password required for full access
doc.isLinearized  // Bool — "Fast Web View" / web-optimised

// Check what the active credential allows
let perms = doc.permissions
if !perms.contains(.copy) { print("Copying is restricted") }
if !perms.contains(.print) { print("Printing is restricted") }
// Available flags: .print .change .copy .addNotes .fillForms
//                 .accessibility .assemble .printHighRes

// Unlock after load (e.g. after prompting the user for a password)
let unlocked = doc.unlock(ownerPassword: "owner123")
```

### Form type

```swift
switch doc.formType {
case .none:     print("No form")
case .acroForm: print("Standard AcroForm — compatible with all viewers")
case .xfa:      print("Adobe XFA — requires specialised viewer")
}
```

### JavaScript

```swift
if doc.hasJavaScript {
    // Log a warning before processing untrusted PDFs
    logger.warning("Document contains embedded JavaScript")
}
```

## Viewer hints

```swift
doc.pageLayout  // PopplerPageLayout: .singlePage, .oneColumn, .twoColumnLeft …
doc.pageMode    // PopplerPageMode: .useOutlines, .useThumbs, .fullScreen …
```

## Document structure

### Table of Contents

```swift
if let toc = doc.tableOfContents() {
    func print(item: PopplerTOCItem, indent: Int = 0) {
        print(String(repeating: "  ", count: indent) + item.title)
        item.children.forEach { print(item: $0, indent: indent + 1) }
    }
    print(item: toc)
}
```

### Named destinations (bookmarks)

```swift
for dest in doc.destinations() {
    // dest.type tells you which coordinate fields are meaningful
    if dest.type == .xyz {
        print("\(dest.name) → page \(dest.pageNumber) at (\(dest.left), \(dest.top))")
    } else {
        print("\(dest.name) → page \(dest.pageNumber) [\(dest.type)]")
    }
}
```

### Embedded file attachments

```swift
guard doc.hasEmbeddedFiles else { return }

for file in doc.embeddedFiles() {
    print("\(file.name) (\(file.mimeType), \(file.size) bytes)")
    if let checksum = file.checksum {
        print("  SHA: \(checksum)")  // hex-encoded
    }
    try file.data.write(to: outputDir.appendingPathComponent(file.name))
}
```

### Fonts

```swift
for font in doc.fonts() {
    print("\(font.name)  type=\(font.type)  embedded=\(font.isEmbedded)  subset=\(font.isSubset)")
}
```

## Iterating pages

```swift
// Async sequence — recommended
for try await page in doc.pages {
    let text = page.text()
}

// Index-based
for i in 0..<doc.pageCount {
    let page = try doc.page(at: i)
    let page = try doc.page(labeled: "A-\(i)")  // by logical label
}
```

## Saving

```swift
// Save with any in-memory modifications
try doc.save(to: outputURL)

// Byte-for-byte copy (faster, no incremental-update overhead)
try doc.saveACopy(to: archiveURL)
```
