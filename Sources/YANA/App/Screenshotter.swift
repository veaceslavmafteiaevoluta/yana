import AppKit

/// Hidden screenshot mode used to generate the README images (see scripts/screenshots.sh).
/// Launch with `-YANAScreenshots <dir>`: renders the notch in several states to PNG files
/// straight from its own view (no Screen Recording permission needed) and then quits.
@MainActor
enum Screenshotter {
    static func runIfRequested(host: NSView) {
        guard let dir = UserDefaults.standard.string(forKey: "YANAScreenshots") else { return }
        let out = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let tabs = (UserDefaults.standard.string(forKey: "YANAScreenshotTabs") ?? "home,audio,widgets,system")
            .split(separator: ",").compactMap { NotchTab(rawValue: String($0)) }
        let vm = NotchViewModel.shared

        var steps: [(TimeInterval, () -> Void)] = []
        // Let services load (track info, artwork, weather) before the first shot.
        steps.append((4.0, { snap(host, out.appendingPathComponent("closed.png")) }))
        steps.append((0.1, { vm.showPeek(.volume, duration: 30) }))
        steps.append((1.0, { snap(host, out.appendingPathComponent("hud-volume.png")) }))
        for tab in tabs {
            steps.append((0.1, { vm.keepOpen = true; vm.open(tab: tab) }))
            steps.append((1.5, { snap(host, out.appendingPathComponent("tab-\(tab.rawValue).png")) }))
        }
        steps.append((0.2, { NSApp.terminate(nil) }))

        var delay: TimeInterval = 0
        for (wait, action) in steps {
            delay += wait
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { action() } }
        }
    }

    private static func snap(_ view: NSView, _ url: URL) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let cg = rep.cgImage, let trimmed = trim(cg, padding: 24) else { return }
        let png = NSBitmapImageRep(cgImage: trimmed).representation(using: .png, properties: [:])
        try? png?.write(to: url)
        NSLog("[YANA] screenshot \(url.path)")
    }

    /// Crops the transparent area around the notch, keeping `padding` px for the shadow.
    private static func trim(_ img: CGImage, padding: Int) -> CGImage? {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 200 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // The context's rows are stored top-down, the same orientation as the cropping rect.
        let r = CGRect(x: max(0, minX - padding), y: max(0, minY - padding),
                       width: min(w, maxX + padding + 1) - max(0, minX - padding),
                       height: min(h, maxY + padding + 1) - max(0, minY - padding))
        return ctx.makeImage()?.cropping(to: r)
    }
}
