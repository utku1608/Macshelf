import AppKit
import SwiftUI

/// Singleton controller for the About window.
/// Lazily created on first access; the window is reused on subsequent shows.
final class AboutWindowController: NSWindowController {

    static let shared: AboutWindowController = {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Macshelf"
        window.isReleasedWhenClosed = false   // keep alive for reuse
        window.isMovableByWindowBackground = true

        let host = NSHostingView(rootView: AboutView())
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()

        return AboutWindowController(window: window)
    }()

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
