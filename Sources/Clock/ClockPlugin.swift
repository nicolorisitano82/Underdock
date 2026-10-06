import AppKit

@objc(ClockDockTilePlugin)
final class ClockDockTilePlugin: TilePlugin {
    private var clockView: ClockTileView? { tileView as? ClockTileView }
    private var lastToken = Int.min

    override func makeTileView() -> TileView {
        ClockTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    /// A hand that sweeps is redrawn fifteen times a second; everything else
    /// once, and even then only if the face would look different — with the
    /// seconds off, that is once a minute.
    ///
    /// Fifteen because the drawing costs 1.4 ms a frame, measured: twenty
    /// milliseconds of work a second, in a process the Dock shares with every
    /// other third-party extra. Sixty would look no better on a tile this size
    /// and would cost four times as much.
    static let sweepRate: TimeInterval = 1.0 / 15

    override var tickInterval: TimeInterval {
        let settings = ClockSettings.current(instanceID)
        return settings.showsSeconds && settings.style.sweeps ? Self.sweepRate : 1
    }

    override func tick() {
        guard let clockView else { return }
        let token = clockView.renderToken(every: tickInterval)
        guard token != lastToken else { return }
        lastToken = token
        refresh()
    }

    override func customMenuItems() -> [NSMenuItem] {
        [
            menuItem(T("Copia l'ora", "Copy the time"), #selector(copyTime)),
            menuItem(T("Apri Calendario", "Open Calendar"), #selector(openCalendar)),
        ]
    }

    @objc private func copyTime() {
        guard let clockView else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clockView.formattedTime, forType: .string)
    }

    @objc private func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
