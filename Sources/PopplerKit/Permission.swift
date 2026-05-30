/// The set of operations the document owner has authorised.
///
/// For **unencrypted** documents all permissions are implicitly granted
/// and `PopplerDocument.permissions` returns `.all`.
/// For **encrypted** documents, permissions reflect the rights granted
/// by the credential level used to open the document.
///
/// ```swift
/// let perms = doc.permissions
/// if !perms.contains(.copy) {
///     print("Copying text is not permitted.")
/// }
/// ```
///
/// Maps to `poppler::permission_enum`.
public struct PopplerPermissions: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// Printing at normal (reduced) resolution is permitted.
    public static let print = PopplerPermissions(rawValue: 1 << 0)
    /// Modifying document content (excluding annotations) is permitted.
    public static let change = PopplerPermissions(rawValue: 1 << 1)
    /// Copying text and graphics is permitted.
    public static let copy = PopplerPermissions(rawValue: 1 << 2)
    /// Adding or modifying annotations and form fields is permitted.
    public static let addNotes = PopplerPermissions(rawValue: 1 << 3)
    /// Filling interactive form fields is permitted.
    public static let fillForms = PopplerPermissions(rawValue: 1 << 4)
    /// Text extraction for accessibility tools is permitted.
    public static let accessibility = PopplerPermissions(rawValue: 1 << 5)
    /// Assembling the document (inserting/deleting pages, bookmarks) is permitted.
    public static let assemble = PopplerPermissions(rawValue: 1 << 6)
    /// Printing at full (high) resolution is permitted.
    public static let printHighRes = PopplerPermissions(rawValue: 1 << 7)

    /// All eight permissions granted.
    public static let all: PopplerPermissions = [
        .print, .change, .copy, .addNotes,
        .fillForms, .accessibility, .assemble, .printHighRes,
    ]
}
