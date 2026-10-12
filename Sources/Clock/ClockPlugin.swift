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
    /// How fast a sweeping hand is redrawn, and it depends on who is looking.
    ///
    /// On a tile at rest the tip of the second hand travels 2.4 px a second,
    /// so eight redraws move it less than a third of a pixel at a time and
    /// nothing is gained by asking for more. Magnified under the pointer it
    /// travels 11.3 px a second and the step only falls under a pixel past
    /// twelve, so there fifteen is worth its 4.9% of a core — and it is spent
    /// for as long as the pointer stays, which is as long as anyone can see it.
    /// Where nothing is heard from the agent, ten splits the difference.
    static let watchedRate: TimeInterval = 1.0 / 15
    static let restingRate: TimeInterval = 1.0 / 8
    static let unattendedRate: TimeInterval = 1.0 / 10

    override var tickInterval: TimeInterval {
        let settings = ClockSettings.current(instanceID)
        guard settings.showsSeconds, settings.style.sweeps else { return 1 }
        switch DockAttention.state {
        case .hot: return Self.watchedRate
        case .cold: return Self.restingRate
        case .unknown: return Self.unattendedRate
        }
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
