import AppKit

/// Watches where the pointer is with respect to the Dock, and says so.
///
/// It lives in the agent because the agent is the only part of Underdock that
/// can see both: a tile plug-in has no pointer and no window, and the manager
/// is usually not running. The answer goes out as a notification and is used
/// by whoever draws something whose pace depends on being looked at — the
/// clock's sweeping hand, for one.
///
/// This used to ride along inside the bar controller, which was wrong in a way
/// that only showed on a Mac without bar widgets: with nothing to anchor, that
/// controller returns early and nothing was ever announced. Here it runs
/// whatever is installed.
final class DockWatcher {
    private var timer: Timer?
    /// Where the Dock is. Asked for rarely: it only moves when the Dock is
    /// resized, hidden or sent to another edge.
    private var dock: NSRect?
    private var dockAskedAt = Date.distantPast
    /// Two lines rather than one, so a pointer resting on the edge does not
    /// cross it several times a second.
    private var isNear = false
    private var heldUntil = Date.distantPast

    func start() {
        stop()
        // Ten times a second: enough that the rate changes while the pointer
        // is still on its way to the Dock, cheap enough to be beneath notice —
        // the whole tick is a mouse position and a rectangle test.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if Date().timeIntervalSince(dockAskedAt) > 1 {
            dockAskedAt = Date()
            dock = DockAccessibility.dockFrame().flatMap { DockAccessibility.flipped($0) }
        }
        guard let dock, dock.height > 4 else {
            // No Dock to be near — hidden, or Accessibility not granted.
            isNear = false
            DockAttention.announce(hot: false)
            return
        }

        if Date() < heldUntil {
            DockAttention.announce(hot: true)
            return
        }

        // Magnification reaches beyond the Dock's own rectangle, and the
        // pointer is usually arriving from above: the band is generous
        // upwards and wider once it has already been entered.
        let reach: CGFloat = isNear ? 2.2 : 1.4
        let band = dock.insetBy(dx: -dock.height * reach, dy: -dock.height * reach)
        isNear = band.contains(NSEvent.mouseLocation)
        if isNear { heldUntil = Date().addingTimeInterval(0.5) }
        DockAttention.announce(hot: isNear)
    }
}
