import CoreGraphics

/// Decides whether a mouse press was a click or a drag.
///
/// This lived inline in the view and got it wrong: it delegated to
/// `performDrag(with:)` and compared pointer positions around that call, but
/// the call returns immediately rather than blocking until mouse-up, so every
/// drag was reported as a click. Extracted here so the rule is pinned by tests.
public struct PressTracker: Equatable {

    public enum Zone: Equatable {
        case none    // not ours — hand the event on
        case move
        case resize
    }

    public enum Outcome: Equatable {
        case ignored  // press began outside a tracked zone
        case click    // never travelled far enough to be a drag
        case moved
        case resized
    }

    /// Slop allowed before a press counts as a drag rather than a click.
    public let threshold: CGFloat

    private var zone: Zone = .none
    private var passedThreshold = false

    public init(threshold: CGFloat = 4) {
        self.threshold = threshold
    }

    public var isTracking: Bool { zone != .none }
    /// True once the press has committed to being a drag.
    public var isDragging: Bool { passedThreshold }

    public mutating func begin(zone: Zone) {
        self.zone = zone
        passedThreshold = false
    }

    /// Reports whether the drag should be applied for this movement.
    /// Once the threshold is passed it stays passed, so easing back toward the
    /// origin mid-drag does not flip the press back into a click.
    public mutating func update(distance: CGFloat) -> Zone? {
        guard zone != .none else { return nil }
        if !passedThreshold && distance < threshold { return nil }
        passedThreshold = true
        return zone
    }

    public mutating func end() -> Outcome {
        defer {
            zone = .none
            passedThreshold = false
        }
        switch (zone, passedThreshold) {
        case (.none, _): return .ignored
        case (_, false): return .click
        case (.move, true): return .moved
        case (.resize, true): return .resized
        }
    }
}
