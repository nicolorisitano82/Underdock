import Foundation

/// A repeating timer that fires on wall-clock boundaries instead of drifting
/// away from them — a clock that ticks 300 ms after the minute looks broken.
final class WallClockTicker {
    private var timer: Timer?
    private let interval: TimeInterval
    private let handler: () -> Void

    init(interval: TimeInterval, handler: @escaping () -> Void) {
        // A tenth of a second was the floor while every tick meant a second
        // being shown; a hand that sweeps asks for fifteen a second. The floor
        // stays, further down, so a mistake somewhere cannot ask for a timer
        // faster than the screen.
        self.interval = max(interval, 1.0 / 60)
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        stop()
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule() {
        let now = Date().timeIntervalSince1970
        let next = (now / interval).rounded(.down) * interval + interval
        let timer = Timer(fire: Date(timeIntervalSince1970: next), interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.handler()
            self.schedule()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
