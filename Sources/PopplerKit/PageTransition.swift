internal import CPopplerBridge

/// The visual style of a page-to-page transition in a PDF presentation.
public enum PopplerPageTransitionType: Int, Sendable {
    case replace = 0
    case split, blinds, box, wipe, dissolve, glitter
    case fly, push, cover, uncover, fade
}

/// The axis along which a split, blinds, or wipe transition operates.
public enum PopplerTransitionAlignment: Int32, Sendable {
    case horizontal = 0
    case vertical = 1
}

/// Whether content moves inward toward the page center or outward toward the edges.
public enum PopplerTransitionDirection: Int32, Sendable {
    case inward = 0
    case outward = 1
}

/// A presentation transition effect applied to a PDF page.
public struct PopplerPageTransition: Sendable {

    /// The visual effect style.
    public let type: PopplerPageTransitionType

    /// Duration of the transition in seconds.
    public let duration: Double

    /// The axis of motion for split, blinds, and wipe transitions.
    public let alignment: PopplerTransitionAlignment

    /// Whether the transition moves inward or outward.
    public let motionDirection: PopplerTransitionDirection

    /// Direction of motion in degrees (e.g. 0 = left-to-right, 90 = bottom-to-top).
    /// Meaningful for wipe, glitter, fly, push, cover, and uncover transitions.
    public let angle: Int

    /// Scale factor (0.0–1.0) for fly transitions.
    public let scale: Double

    /// Whether the transition operates on a rectangular region rather than a circular one.
    public let isRectangular: Bool

    internal init(transitionPtr: PopplerPageTransitionPtr) {
        self.type =
            PopplerPageTransitionType(
                rawValue: Int(poppler_page_transition_get_type(transitionPtr))) ?? .replace
        self.duration = poppler_page_transition_get_duration(transitionPtr)
        self.alignment =
            PopplerTransitionAlignment(
                rawValue: poppler_page_transition_get_alignment(transitionPtr)) ?? .horizontal
        self.motionDirection =
            PopplerTransitionDirection(
                rawValue: poppler_page_transition_get_motion_direction(transitionPtr)) ?? .inward
        self.angle = Int(poppler_page_transition_get_angle(transitionPtr))
        self.scale = poppler_page_transition_get_scale(transitionPtr)
        self.isRectangular = poppler_page_transition_is_rectangular(transitionPtr)
    }
}
