import AppKit
import ApplicationServices

/// Measures the free menu-bar space on both sides of the notch, so the live-activity "ears"
/// never cover the front app's menus (left) or the status items (right).
/// Uses the Accessibility API; without it nothing can be measured and the ears are always shown.
@MainActor
enum MenuBarSpace {
    /// Frames (top-left origin, global coordinates) of the status items, refreshed less often
    /// because they only change when apps launch/quit or add or remove an item.
    private static var statusItems: [CGRect] = []
    private static var statusScannedAt = Date.distantPast

    static func invalidateStatusItems() { statusScannedAt = .distantPast }

    /// True when the notch can grow by `earWidth` per side without covering any menu-bar item.
    static func earsFit(screen: NSScreen, notchWidth: CGFloat, earWidth: CGFloat) -> Bool {
        guard AXIsProcessTrusted() else { return true }
        if Date().timeIntervalSince(statusScannedAt) > 10 {
            statusItems = scanStatusItems()
            statusScannedAt = Date()
        }
        let margin: CGFloat = 6
        let midX = screen.frame.midX
        let leftLimit = midX - notchWidth / 2 - earWidth - margin
        let rightLimit = midX + notchWidth / 2 + earWidth + margin
        // Menu bar band of this screen, in top-left-origin coordinates.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let top = primaryHeight - screen.frame.maxY
        let bar = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, 24)

        for f in frontAppMenus() + statusItems where f.width > 0 && f.minY < top + bar && f.maxY > top {
            guard f.minX < screen.frame.maxX, f.maxX > screen.frame.minX else { continue }
            if f.maxX <= midX, f.maxX > leftLimit { return false }
            if f.minX >= midX, f.minX < rightLimit { return false }
        }
        return true
    }

    /// True while another app shows a pull-down menu (window at the pop-up menu level).
    static func menuIsOpen() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.contains {
            ($0[kCGWindowLayer as String] as? Int) == menuLevel && ($0[kCGWindowOwnerPID as String] as? pid_t) != me
        }
    }

    private static func frontAppMenus() -> [CGRect] {
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        return items(of: app.processIdentifier, attribute: kAXMenuBarAttribute)
    }

    private static func scanStatusItems() -> [CGRect] {
        NSWorkspace.shared.runningApplications
            .flatMap { items(of: $0.processIdentifier, attribute: kAXExtrasMenuBarAttribute) }
    }

    private static func items(of pid: pid_t, attribute: String) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute as CFString, &bar) == .success, let bar,
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return [] }
        return list.compactMap(frame)
    }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
