/// The type of interactive form embedded in a PDF document.
/// Maps to `poppler::document::form_type` (an `enum class`).
public enum PopplerFormType: Int32, Sendable {
    /// No interactive form is present.
    case none = 0
    /// AcroForms — the standard PDF form format, supported by all viewers.
    case acroForm = 1
    /// Adobe XFA (XML Forms Architecture) — requires specialised viewer support.
    /// XFA forms are deprecated in PDF 2.0.
    case xfa = 2
}
