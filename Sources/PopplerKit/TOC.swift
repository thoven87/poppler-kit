internal import CPopplerBridge

/// Represents an item in the Table of Contents (Outline) of a PDF document.
/// This acts as a node in a tree structure.
public struct PopplerTOCItem: Sendable {
    /// The title of the chapter or section.
    public let title: String

    /// Whether this section is expanded (open) by default in a PDF viewer.
    public let isOpen: Bool

    /// The child subsections.
    public let children: [PopplerTOCItem]

    internal init(itemPtr: PopplerTOCItemPtr) {
        self.title = String(cString: poppler_toc_item_get_title(itemPtr))
        self.isOpen = poppler_toc_item_is_open(itemPtr)

        let listPtr = poppler_toc_item_get_children(itemPtr)
        defer { poppler_delete_toc_item_list(listPtr) }

        let size = Int(poppler_toc_item_list_get_size(listPtr))
        var childItems: [PopplerTOCItem] = []
        childItems.reserveCapacity(size)

        for i in 0..<size {
            let childPtr = poppler_toc_item_list_get_item(listPtr, Int32(i))!
            childItems.append(PopplerTOCItem(itemPtr: childPtr))
        }

        self.children = childItems
    }
}
