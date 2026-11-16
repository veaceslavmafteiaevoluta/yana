import SwiftUI
import AppKit

extension NSImage {
    /// Vibrant dominant color: saturation-weighted average, boosted for a "glow" look.
    func ambientColor() -> NSColor? {
        let side = 24
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var r = 0.0, g = 0.0, b = 0.0, wsum = 0.0
        for i in 0..<(side * side) {
            let pr = Double(px[i * 4]) / 255, pg = Double(px[i * 4 + 1]) / 255, pb = Double(px[i * 4 + 2]) / 255
            let mx = max(pr, pg, pb), mn = min(pr, pg, pb)
            let sat = mx > 0 ? (mx - mn) / mx : 0
            let w = sat * sat * mx + 0.02
            r += pr * w; g += pg * w; b += pb * w; wsum += w
        }
        guard wsum > 0 else { return nil }
        let base = NSColor(srgbRed: r / wsum, green: g / wsum, blue: b / wsum, alpha: 1)
        guard let hsb = base.usingColorSpace(.sRGB) else { return base }
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        hsb.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return NSColor(hue: h, saturation: s < 0.12 ? s : max(s, 0.55), brightness: max(v, 0.85), alpha: 1)
    }
}

/// Soft, breathing glow tinted with the artwork color.
struct AmbientGlow: View {
    @EnvironmentObject var media: MediaService
    @EnvironmentObject var settings: Settings
    var anchor: UnitPoint = .topLeading

    var body: some View {
        if settings.ambientLight, media.info != nil {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !(media.isPlaying && settings.ambientPulse))) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let pulse = (media.isPlaying && settings.ambientPulse) ? (sin(t * 2.2) * 0.5 + 0.5) * 0.25 + (sin(t * 5.3) * 0.5 + 0.5) * 0.1 : 0
                let k = settings.ambientIntensity * (0.75 + pulse)
                GeometryReader { g in
                    ZStack {
                        RadialGradient(colors: [media.accent.opacity(0.75 * k), media.accent.opacity(0.25 * k), .clear],
                                       center: anchor, startRadius: 0, endRadius: g.size.width * 0.55)
                        RadialGradient(colors: [media.accentSecondary.opacity(0.45 * k), .clear],
                                       center: UnitPoint(x: 1 - anchor.x, y: 1), startRadius: 0, endRadius: g.size.width * 0.45)
                    }
                    .blur(radius: 30)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.8), value: media.accent)
        }
    }
}
