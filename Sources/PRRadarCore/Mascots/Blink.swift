import Foundation

/// When a character's eyes close.
///
/// Scheduled in seconds rather than in frames, which matters because the two
/// surfaces run at different rates: the drawer at six frames a second, the
/// badge at two so an always-visible panel is not redrawing itself all day. A
/// frame-counted blink would fire three times less often on the slower one, and
/// a character that blinks every twenty seconds reads as frozen rather than calm.
public enum Blink {
    /// Roughly a human resting rate, which is what makes it read as idling
    /// rather than as a glitch.
    public static let interval: Double = 7
    public static let hold: Double = 0.3

    /// Rounded up to at least one frame, so a slow tempo cannot step straight
    /// over the blink window and never close the eyes at all.
    public static func holdFrames(fps: Double) -> Int {
        max(1, Int((hold * max(fps, 1)).rounded()))
    }

    public static func periodFrames(fps: Double) -> Int {
        max(1, Int((interval * max(fps, 1)).rounded()))
    }

    public static func isBlinking(frame: Int, fps: Double) -> Bool {
        guard fps > 0 else { return false }
        let period = periodFrames(fps: fps)
        return ((frame % period) + period) % period < holdFrames(fps: fps)
    }
}
