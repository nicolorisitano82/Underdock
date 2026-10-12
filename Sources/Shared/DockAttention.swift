import Foundation

/// Whether the pointer is on the Dock, passed from the overlay agent to
/// whoever is drawing a tile.
///
/// It exists for one reason: a hand that sweeps is worth redrawing fifteen
/// times a second only while the Dock is magnified under the pointer. On a
/// 27-point tile the tip of the second hand travels 2.4 px a second, so eight
/// redraws already move it less than a third of a pixel at a time; magnified
/// to 128 points it travels 11.3 px a second, and the step only falls under a
/// pixel somewhere past twelve. Measured, both of them — which is why the fast
/// rate is spent exactly where it can be seen and nowhere else.
///
/// The agent is the only process that knows: it reads the tile frames through
/// Accessibility to place its bars, so it has the answer already and need only
/// say it out loud. Where the agent is not running — no bar widgets installed,
/// or it has been killed — nothing is heard and the tile falls back to a rate
/// that is good enough either way.
enum DockAttention {
    static let notification = Notification.Name("dev.nicolo.underdock.dockAttention")

    enum State {
        /// The pointer is on the Dock: tiles are magnified and being watched.
        case hot
        /// The agent is talking, and says the pointer is elsewhere.
        case cold
        /// Nobody is saying. Either there is no agent, or it has gone quiet.
        case unknown
    }

    /// How long a word from the agent is taken as still true. The agent
    /// repeats itself well inside this, so silence means it is gone.
    private static let trusted: TimeInterval = 45
    /// And how often it bothers to repeat itself when nothing has changed.
    private static let repeatAfter: TimeInterval = 15

    private static var heard: (hot: Bool, at: Date)?

    static var state: State {
        guard let heard, Date().timeIntervalSince(heard.at) < trusted else { return .unknown }
        return heard.hot ? .hot : .cold
    }

    // MARK: The agent's side

    private static var announced: (hot: Bool, at: Date)?

    /// Says where the pointer is, if that is news — or if it has been a while
    /// since anybody was told, so that a plug-in starting up late learns it.
    static func announce(hot: Bool) {
        if let announced, announced.hot == hot,
           Date().timeIntervalSince(announced.at) < repeatAfter { return }
        announced = (hot, Date())
        DistributedNotificationCenter.default().postNotificationName(
            notification, object: hot ? "1" : "0", userInfo: nil, deliverImmediately: true
        )
    }

    // MARK: The tile's side

    /// Starts listening. The handler runs after the state has been updated,
    /// on the main queue.
    static func listen(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: notification, object: nil, queue: .main
        ) { note in
            heard = ((note.object as? String) == "1", Date())
            handler()
        }
    }

    static func stopListening(_ token: NSObjectProtocol) {
        DistributedNotificationCenter.default().removeObserver(token)
    }
}
