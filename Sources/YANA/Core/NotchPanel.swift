import AppKit

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        // Must come AFTER isFloatingPanel (which resets the level to .floating = 3).
        // Above the menu bar (24) so the expanded notch covers it.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
    }
    /// macOS pushes windows below the menu bar by default; the notch window must sit at the very top.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
