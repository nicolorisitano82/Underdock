import AppKit
import CoreImage

/// Recolours a folder and stamps a symbol on it, the way macOS 26 lets you
/// customise one in the Finder.
///
/// The colour is a hue rotation rather than a flat fill: the folder keeps its
/// own shading and its edge, and only changes colour — filling it would give
/// back a coloured rectangle in the shape of a folder.
enum FolderIconRenderer {
    /// The hue of the stock folder, measured once: everything rotates from here.
    private static let baseHue: CGFloat = 0.575

    /// What has already been composed, so that a tile being redrawn does not
    /// pay for it again.
    ///
    /// Measured before there was one: composing the icon cost 26.8 ms, and the
    /// folder tile as a whole 47.5 ms a frame — twenty-one frames a second, on
    /// a process the Dock shares with every other third-party extra. None of
    /// the work changes between one frame and the next.
    private struct Key: Hashable {
        var path: String
        var tint: String
        var symbol: String
    }

    private static var cache: [Key: (image: NSImage, made: Date)] = [:]
    /// Long enough to cover any amount of redrawing, short enough that a
    /// folder given a new icon in the Finder catches up on its own.
    private static let keepFor: TimeInterval = 120

    /// Thrown away when the settings change, which is the one moment the
    /// answer is known to be stale.
    static func forget() { cache.removeAll() }

    static func icon(for url: URL?, tintHex: String, symbol: String) -> NSImage {
        let key = Key(path: url?.path ?? "", tint: tintHex, symbol: symbol)
        if let found = cache[key], Date().timeIntervalSince(found.made) < keepFor {
            return found.image
        }
        let composed = compose(for: url, tintHex: tintHex, symbol: symbol)
        // A handful of folders at a time, no more: the cap is there so a
        // long-lived plug-in cannot grow a dictionary for every folder it has
        // ever been pointed at.
        if cache.count > 24 { cache.removeAll() }
        cache[key] = (composed, Date())
        return composed
    }

    /// The icon of a file, at the size it will be drawn.
    ///
    /// The workspace hands back a shared image whose size the caller is
    /// expected to set — and setting it is what picks the representation. Done
    /// on every frame that is both a mutation of something shared and a
    /// rasterisation; done once per size, it is neither.
    static func fileIcon(for path: String, side: CGFloat) -> NSImage {
        let rounded = max(16, (side / 8).rounded() * 8)
        let key = Key(path: path, tint: "file", symbol: "\(Int(rounded))")
        if let found = cache[key], Date().timeIntervalSince(found.made) < keepFor {
            return found.image
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: rounded, height: rounded)
        if cache.count > 24 { cache.removeAll() }
        cache[key] = (icon, Date())
        return icon
    }

    private static func compose(for url: URL?, tintHex: String, symbol: String) -> NSImage {
        let base: NSImage = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .folder)
        // The workspace hands back an image that calls itself 32 points across,
        // and everything downstream — the tint, the stamp, the tile — rasterises
        // at whatever size it claims. Asking for the size we actually want makes
        // it pick the large representation it had all along.
        base.size = NSSize(width: 512, height: 512)

        var image = base
        if let tint = NSColor(hexString: tintHex)?.usingColorSpace(.deviceRGB) {
            image = rotated(base, towards: tint) ?? base
        }
        guard !symbol.isEmpty else { return image }
        return stamped(image, symbol: symbol)
    }

    private static func rotated(_ image: NSImage, towards tint: NSColor) -> NSImage? {
        guard let data = image.tiffRepresentation, let source = CIImage(data: data),
              let filter = CIFilter(name: "CIHueAdjust") else { return nil }

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        tint.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue((hue - baseHue) * 2 * .pi, forKey: kCIInputAngleKey)
        guard var output = filter.outputImage else { return nil }

        // Rotating the hue keeps the stock folder's own saturation, so a
        // vivid red comes back as salmon. The saturation follows the colour
        // that was asked for — and a grey one drains it entirely.
        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(output, forKey: kCIInputImageKey)
            controls.setValue(saturation < 0.12 ? 0 : min(max(saturation * 1.7, 0.7), 2.0),
                              forKey: kCIInputSaturationKey)
            output = controls.outputImage ?? output
        }

        let result = NSImage(size: image.size)
        result.addRepresentation(NSCIImageRep(ciImage: output))
        return result
    }

    private static func stamped(_ image: NSImage, symbol: String) -> NSImage {
        let size = image.size
        let stamped = NSImage(size: size)
        stamped.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))

        // Low on the folder's face and a touch translucent, the way the
        // system's own glyphs sit under the flap rather than on top of it.
        let side = min(size.width, size.height) * 0.34
        let box = NSRect(x: size.width / 2 - side / 2,
                         y: size.height * 0.40 - side / 2,
                         width: side, height: side)
        let configuration = NSImage.SymbolConfiguration(pointSize: side, weight: .medium)
            .applying(NSImage.SymbolConfiguration(
                hierarchicalColor: NSColor(calibratedWhite: 1, alpha: 0.82)))
        if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            let glyphSize = glyph.size
            let scale = min(box.width / glyphSize.width, box.height / glyphSize.height)
            glyph.draw(in: NSRect(x: box.midX - glyphSize.width * scale / 2,
                                  y: box.midY - glyphSize.height * scale / 2,
                                  width: glyphSize.width * scale, height: glyphSize.height * scale),
                       from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
        stamped.unlockFocus()
        return stamped
    }
}
