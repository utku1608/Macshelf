import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    let store = ShelfStore()
    private var panel: NSPanel?

    // Global event monitors — returned tokens must be held to keep them alive.
    private var globalDragMonitor: Any?
    private var globalMouseUpMonitor: Any?

    // Pending hide operation (cancelled if a new drag arrives before it fires).
    private var pendingHide: DispatchWorkItem?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        startDragMonitoring()
        wireStoreCallbacks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = globalDragMonitor   { NSEvent.removeMonitor(m) }
        if let m = globalMouseUpMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Panel

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.acceptsMouseMovedEvents = true
        panel.alphaValue = 0   // hidden until a drag is detected

        // KEY FIX: isMovableByWindowBackground = true hijacks every left-mouse
        // drag on the panel — including SwiftUI's onDrag for shelf items.
        // Moving is handled explicitly in the grip bar via WindowDragger instead.
        panel.isMovableByWindowBackground = false

        let dropView = DropReceivingView(store: store)
        dropView.autoresizingMask = [.width, .height]

        // Wire drag-over events from the drop view to show/hide logic.
        dropView.onDragEntered = { [weak self] in self?.showPanel() }
        dropView.onDragExited  = { [weak self] in self?.scheduleHide() }

        let host = NSHostingView(rootView: ContentView().environment(store))
        host.frame = dropView.bounds
        host.autoresizingMask = [.width, .height]

        // Apply corner radius at the CALayer level so the system window shadow
        // follows the rounded shape instead of the rectangular panel frame.
        host.wantsLayer = true
        host.layer?.cornerRadius   = 22
        host.layer?.cornerCurve    = .continuous   // macOS 26 smooth curves
        host.layer?.masksToBounds  = true

        dropView.addSubview(host)
        panel.contentView = dropView

        place(panel, size: CGSize(width: 88, height: 340))
        // Do NOT call orderFrontRegardless here — panel starts invisible.
        self.panel = panel
    }

    private func place(_ panel: NSPanel, size: CGSize) {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: vis.maxX - size.width - 16,
                y: vis.midY - size.height / 2,
                width:  size.width,
                height: size.height
            ),
            display: false
        )
    }

    // MARK: - Visibility

    func showPanel() {
        pendingHide?.cancel()
        pendingHide = nil
        guard let panel else { return }
        if !panel.isVisible { panel.orderFrontRegardless() }
        guard panel.alphaValue < 1 else { return }  // already fully visible — skip animation
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func scheduleHide(delay: TimeInterval = 0.55) {
        guard store.items.isEmpty else { return }  // stay visible if items remain

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.store.items.isEmpty else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.panel?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard self?.store.items.isEmpty == true else { return }
                self?.panel?.orderOut(nil)
            })
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Global drag monitoring

    private func startDragMonitoring() {
        // Fires when the user drags anything in any app (not just file drags).
        // Global monitor callbacks are delivered on the main thread — no async dispatch needed.
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.showPanel()
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.scheduleHide()
        }
    }

    // MARK: - Store observation

    private func wireStoreCallbacks() {
        // Hide after the user clears all items via the Clear button
        // (no global mouseUp fires in that case).
        store.onBecameEmpty = { [weak self] in
            self?.scheduleHide(delay: 0.4)
        }
    }
}

// MARK: - Drop Receiving View

/// Root NSView of the floating panel.
///
/// Handles NSDraggingDestination natively by reading URLs / text
/// directly from NSPasteboard — reliable in a sandboxed NSPanel.
///
/// NSHostingView (SwiftUI) lives as a CHILD subview. AppKit's drag
/// machinery walks up the superview chain and finds this view's
/// registered types without intercepting ordinary mouse events.
final class DropReceivingView: NSView {

    private let store: ShelfStore
    var onDragEntered: (() -> Void)?
    var onDragExited:  (() -> Void)?

    init(store: ShelfStore) {
        self.store = store
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { store.isTargeted = true }
        onDragEntered?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { store.isTargeted = false }
        onDragExited?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        store.isTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard

        // 1. Local files / folders
        let fileOpts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: fileOpts) as? [URL],
           !urls.isEmpty {
            store.add(urls: urls)
            return true
        }

        // 2. Web / generic URLs
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            store.add(urls: urls)
            return true
        }

        // 3. Plain text
        if let text = pb.string(forType: .string), !text.isEmpty {
            store.add(text: text)
            return true
        }

        return false
    }
}
