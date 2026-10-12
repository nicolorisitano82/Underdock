import AppKit

/// The sky behind the numbers: a gradient, a sun or a moon, clouds that drift,
/// rain that falls, snow that sways, lightning that goes off now and then.
///
/// Drawn from the clock rather than from stored state: every drop knows where
/// it is from the time and its own index, so the same instant draws the same
/// picture and nothing has to be kept between frames. That is what lets the
/// bar in the Dock and the panel in the notch run the same scene at different
/// sizes without either of them owning it.
///
/// It stays behind: the widget's own text has to remain the thing you read, so
/// the sky is painted at low strength and a scrim goes over it.
enum WeatherScene {
    enum Sky {
        case clear, cloudy, overcast, fog, drizzle, rain, snow, storm

        /// The WMO codes, which is what Open-Meteo answers in.
        static func of(_ code: Int) -> Sky {
            switch code {
            case 0, 1: return .clear
            case 2: return .cloudy
            case 3: return .overcast
            case 45, 48: return .fog
            case 51, 53, 55, 56, 57: return .drizzle
            case 61, 63, 65, 66, 67, 80, 81, 82: return .rain
            case 71, 73, 75, 77, 85, 86: return .snow
            case 95, 96, 99: return .storm
            default: return .cloudy
            }
        }

        /// How much of the picture is weather rather than sky.
        var drops: Int {
            switch self {
            case .drizzle: return 18
            case .rain: return 30
            case .storm: return 38
            case .snow: return 22
            default: return 0
            }
        }

        var hasClouds: Bool {
            switch self {
            case .clear: return false
            case .cloudy: return true
            default: return true
            }
        }
    }

    /// Paints the sky into `plate`, clipped to its rounded corners.
    ///
    /// `strength` is how much of it shows through — the bar in the Dock is a
    /// small thing next to its neighbours and wants less of it than the panel
    /// in the notch, which has room to be a picture.
    static func draw(in plate: NSRect, radius: CGFloat, code: Int, isNight: Bool,
                     wind: Double, at time: TimeInterval, strength: CGFloat = 1) {
        let sky = Sky.of(code)
        let height = plate.height

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius).addClip()

        gradient(for: sky, night: isNight, strength: strength).draw(in: plate, angle: -90)

        if sky == .clear && isNight { stars(in: plate, at: time, strength: strength) }
        if sky == .clear || sky == .cloudy {
            celestial(in: plate, night: isNight, at: time, strength: strength)
        }
        if sky.hasClouds {
            clouds(in: plate, sky: sky, night: isNight, wind: wind, at: time, strength: strength)
        }
        if sky == .fog { fog(in: plate, at: time, strength: strength) }
        if sky == .storm { lightning(in: plate, at: time, strength: strength) }

        let count = Int(CGFloat(sky.drops) * min(max(plate.width / 240, 0.45), 2.2))
        if count > 0 {
            if sky == .snow {
                snow(in: plate, count: count, at: time, strength: strength)
            } else {
                rain(in: plate, count: count, sky: sky, wind: wind, at: time, strength: strength)
            }
        }

        // The scrim: without it the text sits on whatever the sky happens to
        // be doing underneath, and a white cloud passing under a white figure
        // takes it away.
        let scrim = NSGradient(colors: [
            NSColor(calibratedWhite: isNight ? 0 : 0.08, alpha: 0.34 * strength),
            NSColor(calibratedWhite: isNight ? 0 : 0.08, alpha: 0.10 * strength),
        ])
        scrim?.draw(in: plate, angle: -90)
        _ = height
    }

    // MARK: The sky itself

    private static func gradient(for sky: Sky, night: Bool, strength: CGFloat) -> NSGradient {
        let pair: (NSColor, NSColor)
        switch (sky, night) {
        case (.clear, false):
            pair = (rgb(0.26, 0.60, 0.96), rgb(0.62, 0.83, 0.99))
        case (.clear, true):
            pair = (rgb(0.04, 0.07, 0.20), rgb(0.12, 0.17, 0.38))
        case (.cloudy, false):
            pair = (rgb(0.40, 0.62, 0.86), rgb(0.72, 0.80, 0.88))
        case (.cloudy, true):
            pair = (rgb(0.08, 0.11, 0.22), rgb(0.20, 0.24, 0.34))
        case (.overcast, _), (.fog, _):
            pair = night ? (rgb(0.12, 0.13, 0.16), rgb(0.22, 0.23, 0.26))
                         : (rgb(0.52, 0.56, 0.62), rgb(0.72, 0.75, 0.79))
        case (.drizzle, _), (.rain, _):
            pair = night ? (rgb(0.07, 0.10, 0.18), rgb(0.16, 0.21, 0.30))
                         : (rgb(0.33, 0.43, 0.56), rgb(0.55, 0.63, 0.72))
        case (.snow, _):
            pair = night ? (rgb(0.10, 0.12, 0.20), rgb(0.22, 0.26, 0.36))
                         : (rgb(0.57, 0.64, 0.74), rgb(0.80, 0.84, 0.90))
        case (.storm, _):
            pair = (rgb(0.10, 0.11, 0.18), rgb(0.26, 0.28, 0.38))
        }
        return NSGradient(colors: [pair.0.withAlphaComponent(strength),
                                   pair.1.withAlphaComponent(strength)])
            ?? NSGradient(starting: pair.0, ending: pair.1)!
    }

    /// The sun, or the moon, with a glow that breathes.
    private static func celestial(in plate: NSRect, night: Bool, at time: TimeInterval,
                                  strength: CGFloat) {
        let side = plate.height * 0.46
        let centre = NSPoint(x: plate.maxX - plate.height * 0.42,
                             y: plate.maxY - plate.height * 0.34)
        // Slow, and never all the way: a sun that pulses hard reads as a
        // warning light rather than as weather.
        let breath = 1 + 0.06 * CGFloat(sin(time * 1.1))

        if night {
            let moon = NSRect(x: centre.x - side * 0.34, y: centre.y - side * 0.34,
                              width: side * 0.68, height: side * 0.68)
            glow(at: centre, radius: side * 1.1 * breath,
                 colour: rgb(0.85, 0.88, 1), strength: 0.30 * strength)
            rgb(0.93, 0.95, 1).withAlphaComponent(0.92 * strength).setFill()
            NSBezierPath(ovalIn: moon).fill()
            // The bite that makes a disc a moon: the sky painted back over
            // one side of it, which is the only way to take a piece out of
            // something already drawn.
            let bite = moon.offsetBy(dx: side * 0.22, dy: side * 0.12)
            rgb(0.06, 0.09, 0.24).withAlphaComponent(0.92 * strength).setFill()
            NSBezierPath(ovalIn: bite).fill()
            return
        }

        glow(at: centre, radius: side * 1.5 * breath,
             colour: rgb(1, 0.86, 0.42), strength: 0.45 * strength)
        rgb(1, 0.91, 0.55).withAlphaComponent(0.95 * strength).setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - side * 0.3, y: centre.y - side * 0.3,
                                    width: side * 0.6, height: side * 0.6)).fill()

        // Rays, turning once a minute.
        let rays = 8
        let turn = time * .pi / 30
        rgb(1, 0.89, 0.5).withAlphaComponent(0.35 * strength).setStroke()
        for index in 0..<rays {
            let angle = turn + CGFloat(index) * (.pi * 2 / CGFloat(rays))
            let inner = side * 0.42 * breath
            let outer = side * (0.62 + 0.06 * CGFloat(sin(time * 1.7 + CGFloat(index))))
            let path = NSBezierPath()
            path.lineWidth = max(1, plate.height * 0.022)
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: centre.x + cos(angle) * inner,
                                  y: centre.y + sin(angle) * inner))
            path.line(to: NSPoint(x: centre.x + cos(angle) * outer,
                                  y: centre.y + sin(angle) * outer))
            path.stroke()
        }
    }

    private static func glow(at centre: NSPoint, radius: CGFloat, colour: NSColor,
                             strength: CGFloat) {
        let gradient = NSGradient(colors: [colour.withAlphaComponent(strength),
                                           colour.withAlphaComponent(0)])
        gradient?.draw(fromCenter: centre, radius: 0, toCenter: centre, radius: radius,
                       options: [])
    }

    private static func stars(in plate: NSRect, at time: TimeInterval, strength: CGFloat) {
        let count = Int(min(max(plate.width / 26, 6), 30))
        for index in 0..<count {
            let x = plate.minX + random(index, 7) * plate.width
            let y = plate.minY + plate.height * (0.45 + random(index, 11) * 0.5)
            let twinkle = 0.35 + 0.4 * CGFloat(abs(sin(time * 0.9 + random(index, 3) * 6)))
            let side = plate.height * (0.02 + random(index, 5) * 0.02)
            NSColor.white.withAlphaComponent(twinkle * strength).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: side, height: side)).fill()
        }
    }

    // MARK: Weather

    private static func clouds(in plate: NSRect, sky: Sky, night: Bool, wind: Double,
                               at time: TimeInterval, strength: CGFloat) {
        let count: Int
        switch sky {
        case .clear: count = 0
        case .cloudy: count = 3
        case .drizzle, .rain, .snow, .storm: count = 4
        default: count = 3
        }
        guard count > 0 else { return }

        // The wind the reading gives, slowed down to something a cloud does.
        let speed = 6 + min(max(wind, 0), 60) * 0.5
        let white = night ? rgb(0.62, 0.66, 0.76) : .white
        let alpha = (sky == .overcast || sky == .storm ? 0.42 : 0.30) * strength

        for index in 0..<count {
            let scale = 0.7 + random(index, 13) * 0.6
            let width = plate.height * 1.7 * scale
            let span = Double(plate.width + width * 2)
            // Each cloud starts somewhere else along the run. Without the
            // offset they all leave the right edge together and the sky is
            // empty for most of the loop — which is exactly how the first
            // version looked.
            let drift = CGFloat((time * speed * Double(0.6 + random(index, 17) * 0.8)
                                 + Double(random(index, 71)) * span)
                .truncatingRemainder(dividingBy: span))
            let x = plate.maxX + width - drift
            // Rain falls from somewhere: under a sky that is precipitating the
            // clouds keep to the top, where the drops start.
            let band: (CGFloat, CGFloat) = sky == .cloudy ? (0.52, 0.34) : (0.70, 0.26)
            let y = plate.minY + plate.height * (band.0 + random(index, 19) * band.1)
            cloud(at: NSPoint(x: x, y: y), width: width,
                  colour: white.withAlphaComponent(alpha * (0.7 + 0.3 * scale)))
        }
    }

    /// Five overlapping discs, which is all a cloud is at this size.
    ///
    /// Ovals only: the first version closed the bottom with a rounded
    /// rectangle and the corner of it showed, which made the cloud look like a
    /// box with bumps on. Overlapping discs of the right sizes give a flat
    /// enough base on their own.
    private static func cloud(at centre: NSPoint, width: CGFloat, colour: NSColor) {
        let height = width * 0.42
        colour.setFill()
        let path = NSBezierPath()
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [
            // offset from the centre, how far up, how big
            (-0.40, -0.02, 0.44),
            (-0.14,  0.12, 0.60),
            ( 0.14,  0.04, 0.52),
            ( 0.38, -0.04, 0.40),
            ( 0.00, -0.12, 0.74),
        ]
        for (dx, dy, size) in puffs {
            let side = width * size
            path.appendOval(in: NSRect(x: centre.x + width * dx - side / 2,
                                       y: centre.y + height * dy - side * 0.34,
                                       width: side, height: side * 0.68))
        }
        path.fill()
    }

    private static func rain(in plate: NSRect, count: Int, sky: Sky, wind: Double,
                             at time: TimeInterval, strength: CGFloat) {
        let slant = CGFloat(min(max(wind, 0), 60)) / 60 * 0.55
        let length = plate.height * (sky == .drizzle ? 0.14 : 0.22)
        let speed = plate.height * (sky == .drizzle ? 1.6 : 2.6)
        let colour = rgb(0.80, 0.90, 1).withAlphaComponent((sky == .drizzle ? 0.40 : 0.55) * strength)
        colour.setStroke()

        for index in 0..<count {
            let lane = random(index, 23)
            let fall = CGFloat((time * Double(speed) * Double(0.8 + random(index, 29) * 0.5)
                                + Double(random(index, 31)) * Double(plate.height * 2))
                .truncatingRemainder(dividingBy: Double(plate.height + length * 2)))
            let top = plate.maxY + length - fall
            let x = plate.minX + lane * plate.width + slant * (plate.maxY - top)
            let path = NSBezierPath()
            path.lineWidth = max(0.8, plate.height * 0.018)
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: x, y: top))
            path.line(to: NSPoint(x: x - slant * length, y: top - length))
            path.stroke()
        }
    }

    private static func snow(in plate: NSRect, count: Int, at time: TimeInterval,
                             strength: CGFloat) {
        let speed = plate.height * 0.42
        for index in 0..<count {
            let side = plate.height * (0.03 + random(index, 37) * 0.035)
            let fall = CGFloat((time * Double(speed) * Double(0.6 + random(index, 41) * 0.7)
                                + Double(random(index, 43)) * Double(plate.height * 2))
                .truncatingRemainder(dividingBy: Double(plate.height + side * 2)))
            let y = plate.maxY + side - fall
            let sway = CGFloat(sin(time * 1.3 + Double(random(index, 47)) * 6)) * plate.height * 0.09
            let x = plate.minX + random(index, 53) * plate.width + sway
            NSColor.white.withAlphaComponent((0.55 + random(index, 59) * 0.35) * strength).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: side, height: side)).fill()
        }
    }

    private static func fog(in plate: NSRect, at time: TimeInterval, strength: CGFloat) {
        for index in 0..<3 {
            let height = plate.height * (0.16 + random(index, 61) * 0.12)
            let y = plate.minY + plate.height * (0.18 + CGFloat(index) * 0.26)
            let drift = CGFloat((time * Double(8 + index * 4))
                .truncatingRemainder(dividingBy: Double(plate.width * 2)))
            let x = plate.maxX - drift
            NSColor.white.withAlphaComponent((0.16 - CGFloat(index) * 0.03) * strength).setFill()
            for repetition in 0..<2 {
                let band = NSRect(x: x + CGFloat(repetition) * plate.width * 2 - plate.width,
                                  y: y, width: plate.width * 1.4, height: height)
                NSBezierPath(roundedRect: band, xRadius: height / 2, yRadius: height / 2).fill()
            }
        }
    }

    /// A flash every few seconds, and a second one right behind it.
    private static func lightning(in plate: NSRect, at time: TimeInterval, strength: CGFloat) {
        let period = 3.7
        let into = time.truncatingRemainder(dividingBy: period)
        let flash: CGFloat
        switch into {
        case ..<0.06: flash = 0.55
        case 0.10..<0.14: flash = 0.38
        default: flash = 0
        }
        guard flash > 0 else { return }
        NSColor.white.withAlphaComponent(flash * strength).setFill()
        plate.fill()
    }

    // MARK: Odds and ends

    /// A number between 0 and 1 that is always the same for the same pair, so
    /// a drop keeps its lane from one frame to the next without anything being
    /// stored.
    private static func random(_ index: Int, _ salt: Int) -> CGFloat {
        var value = UInt64(truncatingIfNeeded: (index &+ 1) &* 2_654_435_761
                            &+ salt &* 40_503)
        value ^= value >> 13
        value = value &* 1_274_126_177
        value ^= value >> 16
        return CGFloat(value % 10_000) / 10_000
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}
