// MARK: - Pure-Swift string helpers
//
// FoundationEssentials on Linux does not expose CharacterSet or the
// Foundation String extensions that depend on it (trimmingCharacters,
// localizedCaseInsensitiveContains).  These package-level helpers replace
// them with pure-Swift equivalents so PopplerKit and PopplerLayout remain
// libcurl-free on Linux.
//
// package access — visible to PopplerKit and PopplerLayout within this
// package, but not exported as public API.

extension StringProtocol {
    /// Removes leading and trailing whitespace (including newlines).
    ///
    /// Equivalent to `trimmingCharacters(in: .whitespacesAndNewlines)`.
    /// `Character.isWhitespace` covers spaces, tabs, newlines, and all
    /// Unicode whitespace — a superset of both `.whitespaces` and
    /// `.whitespacesAndNewlines`.
    package func trimmingWhitespace() -> String {
        guard let first = firstIndex(where: { !$0.isWhitespace }),
            let last = lastIndex(where: { !$0.isWhitespace })
        else { return "" }
        return String(self[first...last])
    }
}
