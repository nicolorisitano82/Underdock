import AppKit

final class ClockTileView: TileView {
    private lazy var settings = ClockSettings.current(resolvedInstance("clock"))
    private let timeFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()
    private var localeObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rebuildFormatters()
        for name in [NSLocale.currentLocaleDidChangeNotification, Notification.Name.NSSystemTimeZoneDidChange] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.rebuildFormatters()
                self?.needsDisplay = true
            }
            localeObservers.append(token)
        }
    }

    deinit {
        localeObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Pinned instant used when rendering app icons, where "now" would be wrong.
    var fixedDate: Date?

    private var renderDate: Date { fixedDate ?? Date() }

    override func reloadSettings() {
        settings = ClockSettings.current(resolvedInstance("clock"))
        accent = settings.accent
        rebuildFormatters()
        needsDisplay = true
    }

    private func rebuildFormatters() {
        timeFormatter.locale = .autoupdatingCurrent
        timeFormatter.timeZone = settings.timeZone
        timeFormatter.dateFormat = settings.timeFormat()

        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.timeZone = settings.timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("EEE d")
    }

    /// What the tile currently shows, so the plug-in can skip redraws that would
    /// paint the same pixels.
    /// What makes this frame different from the last one.
    ///
    /// `every` is how finely the caller intends to look: a sweeping hand asks
    /// fifteen times a second and wants a different answer each time, while a
    /// face without seconds changes once a minute and should say so, so that
    /// the redraw — and the trip across to the Dock — can be skipped.
    func renderToken(at date: Date = Date(), every interval: TimeInterval = 1) -> Int {
        let unit: TimeInterval = settings.showsSeconds ? max(interval, 0.01) : 60
        return Int(date.timeIntervalSince1970 / unit)
    }

    var formattedTime: String { timeFormatter.string(from: Date()) }

    override func draw(_ dirtyRect: NSRect) {
        let card = drawCard()
        let now = renderDate
        settings.style.face.draw(ClockFaceContext(
            card: card,
            date: now,
            settings: settings,
            palette: palette,
            timeText: timeFormatter.string(from: now),
            dateText: dateFormatter.string(from: now)
        ))
    }
}
