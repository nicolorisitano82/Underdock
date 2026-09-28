import AppKit

/// The camera effects macOS offers in Control Centre while something is
/// filming: the ring light, and Studio Light beside it.
///
/// AVFoundation only lets an app read whether Studio Light is on — the public
/// property is class-level and read-only. The switches live in a private corner
/// of AVFCapture, where Control Centre's own module calls them, and they are
/// reached here by name at run time. Everything is per bundle identifier, so
/// turning something on for us leaves FaceTime's own setting alone.
///
/// Being private, they are allowed to move, and in macOS 27.2 they did: the
/// colour-recommendation switch went away, and asking for the *intensity* of
/// the ring light — which used to answer — now throws. So every entry point is
/// looked up on its own and used only if it is there. An earlier version took
/// them in one guard, which meant a single missing name cost the whole feature
/// in silence: the light simply stopped coming on.
enum VideoEffects {
    private typealias GetForEffect = @convention(c) (CFString, CFString) -> Bool
    private typealias SetForEffect = @convention(c) (CFString, Bool, CFString) -> Void
    private typealias GetFloatForEffect = @convention(c) (CFString, CFString) -> Float
    private typealias SetFloatForEffect = @convention(c) (CFString, Float, CFString) -> Void
    private typealias GetBool = @convention(c) (CFString) -> Bool
    private typealias SetBool = @convention(c) (Bool, CFString) -> Void
    private typealias GetFloat = @convention(c) (CFString) -> Float
    private typealias SetFloat = @convention(c) (Float, CFString) -> Void

    private static let path =
        "/System/Library/PrivateFrameworks/AVFCapture.framework/AVFCapture"
    private static let handle: UnsafeMutableRawPointer? = dlopen(path, RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let address = dlsym(handle, name) else {
            missing.insert(name)
            return nil
        }
        return unsafeBitCast(address, to: T.self)
    }

    private static func constant(_ name: String) -> CFString? {
        guard let handle, let address = dlsym(handle, name) else {
            missing.insert(name)
            return nil
        }
        return address.assumingMemoryBound(to: CFString?.self).pointee
    }

    /// Whatever this macOS does not have, said once: the next time Apple moves
    /// something, the log says which name went rather than nothing at all.
    private static var missing: Set<String> = [] {
        didSet {
            guard missing.count != oldValue.count else { return }
            Diagnostics.once("videoeffects.\(missing.count)",
                             "effetti video, nomi assenti: \(missing.sorted().joined(separator: ", "))")
        }
    }

    private static let ringKey = constant("AVControlCenterVideoEffectRingLight")
    private static let studioKey = constant("AVControlCenterVideoEffectStudioLighting")

    private static let prefix = "AVControlCenterVideoEffectsModule"
    private static let isSupported = symbol("\(prefix)IsEffectSupportedForBundleID",
                                            as: GetForEffect.self)
    private static let isEnabled = symbol("\(prefix)IsEffectEnabledForBundleID",
                                          as: GetForEffect.self)
    private static let setEnabled = symbol("\(prefix)SetEffectEnabledForBundleID",
                                           as: SetForEffect.self)
    private static let effectIntensity = symbol("\(prefix)GetEffectIntensityForBundleID",
                                                as: GetFloatForEffect.self)
    private static let setEffectIntensity = symbol("\(prefix)SetEffectIntensityForBundleID",
                                                   as: SetFloatForEffect.self)
    private static let isRingActive = symbol("\(prefix)GetRingLightActiveForBundleID",
                                             as: GetBool.self)
    private static let setRingActive = symbol("\(prefix)SetRingLightActiveForBundleID",
                                              as: SetBool.self)
    private static let getRingColour = symbol("\(prefix)GetRingLightColorForBundleID",
                                              as: GetFloat.self)
    private static let setRingColour = symbol("\(prefix)SetRingLightColorForBundleID",
                                              as: SetFloat.self)
    private static let getRingWidth = symbol("\(prefix)GetRingLightWidthForBundleID",
                                             as: GetFloat.self)
    private static let setRingWidth = symbol("\(prefix)SetRingLightWidthForBundleID",
                                             as: SetFloat.self)
    /// Two names for the same idea — the system choosing the colour itself and
    /// putting ours back. The first is what macOS 27.2 has; the second is what
    /// came before it.
    private static let setAutoColour = symbol("\(prefix)SetRingLightAutoColorEnabledForBundleID",
                                              as: SetBool.self)
    private static let setColourAdvice =
        symbol("\(prefix)SetRingLightColorRecommendationEnabledForBundleID", as: SetBool.self)

    /// The identifier the effect is set for: this process, whichever it is.
    private static var bundleID: CFString {
        (Bundle.main.bundleIdentifier ?? "dev.nicolo.underdock") as CFString
    }

    // MARK: Studio Light

    static var isStudioLightSupported: Bool {
        guard let isSupported, let studioKey else { return false }
        return isSupported(studioKey, bundleID)
    }

    static var isStudioLightOn: Bool {
        guard let isEnabled, let studioKey else { return false }
        return isEnabled(studioKey, bundleID)
    }

    @discardableResult
    static func setStudioLight(_ on: Bool) -> Bool {
        guard let setEnabled, let studioKey, isStudioLightSupported else { return false }
        setEnabled(studioKey, on, bundleID)
        return true
    }

    // MARK: The ring light

    /// Whether the screen is being used as a light right now.
    static var isRingLightOn: Bool {
        guard let isRingActive else { return false }
        return isRingActive(bundleID)
    }

    static var isRingLightSupported: Bool {
        guard let isSupported, let ringKey else { return false }
        return isSupported(ringKey, bundleID)
    }

    static func setRingLight(_ on: Bool) {
        setRingActive?(on, bundleID)
        // The effect and its switch are two different things: one says the
        // light exists, the other that it is shining.
        if let setEnabled, let ringKey { setEnabled(ringKey, on, bundleID) }
    }

    /// How much light, 0 to 1.
    ///
    /// The width of the ring, not the effect's intensity: on macOS 27.2 asking
    /// the intensity of the ring light raises *Invalid Video Effect Argument*
    /// and takes the application down with it — measured. The width is the knob
    /// that is still there, it is the one that changes what the screen shows,
    /// and it keeps a floor: a ring thinned to nothing is a light switched off
    /// by another name, and the switch above already does that.
    private static let floorWidth: Float = 0.2

    static var ringLightIntensity: Float {
        guard let getRingWidth else { return 0.5 }
        let width = getRingWidth(bundleID)
        guard width.isFinite else { return 0.5 }
        return min(max((width - floorWidth) / (1 - floorWidth), 0), 1)
    }

    static func setRingLightIntensity(_ value: Float) {
        guard let setRingWidth else { return }
        let wanted = min(max(value, 0), 1)
        setRingWidth(floorWidth + wanted * (1 - floorWidth), bundleID)
    }

    /// Where the light sits between amber and daylight. Measured, not guessed:
    /// 0 is `1.00 0.63 0.19`, 0.5 is white, 1 is `0.73 0.82 1.00`.
    ///
    /// Five stops across the whole scale: two of them a tenth apart, which is
    /// what the first version offered, are not a choice anybody can see.
    static let lightStops: [Float] = [0, 0.25, 0.5, 0.75, 1]
    static let warmLight: Float = 0
    static let whiteLight: Float = 0.5

    static func lightName(_ value: Float) -> String {
        switch value {
        case ..<0.13: return T("Ambra", "Amber")
        case ..<0.38: return T("Dorata", "Golden")
        case ..<0.63: return T("Bianca", "White")
        case ..<0.88: return T("Fredda", "Cool")
        default: return T("Azzurra", "Blue")
        }
    }

    /// The colour the system will actually shine, so a swatch can show it
    /// rather than approximate it.
    static func lightColour(_ value: Float) -> NSColor {
        guard let converted = converter?(min(max(value, 0), 1))?.takeUnretainedValue(),
              let colour = NSColor(cgColor: converted) else {
            // Between the two ends that were measured, which is close enough
            // when the private converter is not there.
            let warm = NSColor(calibratedRed: 1, green: 0.63, blue: 0.19, alpha: 1)
            let cool = NSColor(calibratedRed: 0.73, green: 0.82, blue: 1, alpha: 1)
            return warm.blended(withFraction: CGFloat(value), of: cool) ?? .white
        }
        return colour
    }

    private typealias Converter = @convention(c) (Float) -> Unmanaged<CGColor>?

    private static let converter: Converter? =
        symbol("\(prefix)ConvertNormalizedRingLightColorToRGBColor", as: Converter.self)

    static var ringLightColour: Float {
        guard let getRingColour else { return whiteLight }
        return getRingColour(bundleID)
    }

    static func setRingLightColour(_ value: Float) {
        // The system offers a colour of its own and would put ours back, so it
        // is told not to. Which call does that depends on the macOS: the newer
        // one calls it auto colour, the older one a recommendation.
        setAutoColour?(false, bundleID)
        setColourAdvice?(false, bundleID)
        setRingColour?(min(max(value, 0), 1), bundleID)
        reapply()
    }

    /// Makes the light look at its settings again, after a colour change that
    /// it would otherwise not notice.
    ///
    /// Switching it off and on does not do it — tried, with a pause between the
    /// two and without. What it follows is the amount of light: move that and
    /// the light comes back the new colour. So it is moved by a fortieth and
    /// put straight back, which is under what an eye catches and enough for the
    /// light to read the rest.
    private static func reapply() {
        guard let getRingWidth, let setRingWidth, isRingLightOn else { return }
        let width = getRingWidth(bundleID)
        guard width.isFinite else { return }
        let nudged = width > 0.5 ? width - 0.03 : width + 0.03
        setRingWidth(nudged, bundleID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            setRingWidth(width, bundleID)
        }
    }

    /// Studio Light's own amount, which still answers where the ring's does
    /// not. Kept apart from the ring's so that one going wrong cannot take the
    /// other with it.
    static var studioLightIntensity: Float {
        guard let effectIntensity, let studioKey, isStudioLightSupported else { return 0.5 }
        return effectIntensity(studioKey, bundleID)
    }

    static func setStudioLightIntensity(_ value: Float) {
        guard let setEffectIntensity, let studioKey, isStudioLightSupported else { return }
        setEffectIntensity(studioKey, min(max(value, 0), 1), bundleID)
    }
}
