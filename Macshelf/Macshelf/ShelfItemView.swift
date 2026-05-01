import SwiftUI
import AppKit

// MARK: - Public SwiftUI wrapper

/// SwiftUI entry-point for a shelf item.
/// Backed by ItemDragView so we get NSDraggingSource lifecycle callbacks
/// that SwiftUI's `onDrag` does not expose — specifically the
/// `draggingSession(_:endedAt:operation:)` delegate that tells us whether
/// the drop was accepted, letting us remove the item automatically.
struct ShelfItemView: NSViewRepresentable {
    let item: ShelfItem
    let isSelected: Bool
    let onRemove: () -> Void
    let onRemoveSelected: () -> Void
    let onToggleSelection: () -> Void
    let onClearSelection: () -> Void
    /// Called at drag-initiation time to read live selection from the store.
    let onGetSelectedItems: () -> [ShelfItem]

    func makeNSView(context: Context) -> ItemDragView {
        ItemDragView(item: item, isSelected: isSelected,
                     onRemove: onRemove, onRemoveSelected: onRemoveSelected,
                     onToggleSelection: onToggleSelection, onClearSelection: onClearSelection,
                     onGetSelectedItems: onGetSelectedItems)
    }

    func updateNSView(_ nsView: ItemDragView, context: Context) {
        nsView.update(item: item, isSelected: isSelected,
                      onRemove: onRemove, onRemoveSelected: onRemoveSelected,
                      onToggleSelection: onToggleSelection, onClearSelection: onClearSelection,
                      onGetSelectedItems: onGetSelectedItems)
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: ItemDragView,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 64, height: 80)
    }
}

// MARK: - Drag-capable NSView

final class ItemDragView: NSView, NSDraggingSource {

    private(set) var item: ShelfItem
    private(set) var isSelected: Bool
    private(set) var onRemove: () -> Void
    private(set) var onRemoveSelected: () -> Void
    private(set) var onToggleSelection: () -> Void
    private(set) var onClearSelection: () -> Void
    private(set) var onGetSelectedItems: () -> [ShelfItem]

    private var host: NSHostingView<ItemVisual>!
    private var mouseDownPt: NSPoint = .zero
    private var dragActive = false
    private var isMultiDrag = false
    private var isHovering = false { didSet { refreshVisual() } }
    private var hoverTrackingArea: NSTrackingArea?

    // MARK: Init

    init(item: ShelfItem, isSelected: Bool,
         onRemove: @escaping () -> Void, onRemoveSelected: @escaping () -> Void,
         onToggleSelection: @escaping () -> Void, onClearSelection: @escaping () -> Void,
         onGetSelectedItems: @escaping () -> [ShelfItem]) {
        self.item = item
        self.isSelected = isSelected
        self.onRemove = onRemove
        self.onRemoveSelected = onRemoveSelected
        self.onToggleSelection = onToggleSelection
        self.onClearSelection = onClearSelection
        self.onGetSelectedItems = onGetSelectedItems
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(item: ShelfItem, isSelected: Bool,
                onRemove: @escaping () -> Void, onRemoveSelected: @escaping () -> Void,
                onToggleSelection: @escaping () -> Void, onClearSelection: @escaping () -> Void,
                onGetSelectedItems: @escaping () -> [ShelfItem]) {
        // Only touch the hosted SwiftUI view when pixels actually change.
        // Closure updates (every render) and non-visual state never force a redraw.
        let needsVisualRefresh = (self.isSelected != isSelected)
        self.item = item
        self.isSelected = isSelected
        self.onRemove = onRemove
        self.onRemoveSelected = onRemoveSelected
        self.onToggleSelection = onToggleSelection
        self.onClearSelection = onClearSelection
        self.onGetSelectedItems = onGetSelectedItems
        toolTip = item.displayName
        if needsVisualRefresh { refreshVisual() }
    }

    private func setup() {
        host = NSHostingView(rootView: makeVisual())
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        toolTip = item.displayName

        // Right-click → remove
        let removeItem = NSMenuItem(title: "Remove", action: #selector(handleRemove), keyEquivalent: "")
        removeItem.target = self
        let menu = NSMenu()
        menu.addItem(removeItem)
        self.menu = menu
    }

    private func makeVisual() -> ItemVisual {
        ItemVisual(item: item, isHovering: isHovering, isSelected: isSelected)
    }

    private func refreshVisual() {
        host.rootView = makeVisual()
    }

    @objc private func handleRemove() {
        withAnimation(.spring(response: 0.3)) { onRemove() }
    }

    // MARK: - Hit testing
    //
    // Return self for all points within our frame so that mouseDown /
    // mouseDragged reach us before NSHostingView can consume them.
    // This lets us call beginDraggingSession ourselves.

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove only OUR tracking area — not the system-managed one that
        // powers NSView.toolTip. Removing all tracking areas kills tooltips.
        if let old = hoverTrackingArea { removeTrackingArea(old) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        hoverTrackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent)  { isHovering = false }

    // MARK: - Selection + drag initiation

    override func mouseDown(with event: NSEvent) {
        mouseDownPt = event.locationInWindow
        dragActive = false

        if event.modifierFlags.contains(.command) {
            // Cmd+Click: add/remove this item from the selection set.
            onToggleSelection()
        } else if !isSelected {
            // Plain click on an unselected item: collapse any existing selection.
            // (Plain click on a selected item does nothing here so the user can
            //  drag the whole selection without collapsing it first.)
            onClearSelection()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragActive else { return }
        let loc = event.locationInWindow
        guard hypot(loc.x - mouseDownPt.x, loc.y - mouseDownPt.y) > 4 else { return }
        dragActive = true

        // Read live selection from the store — not self.isSelected, which
        // may lag one render cycle behind after a mouseDown selection change.
        let selected = onGetSelectedItems()
        if selected.count > 1 && selected.contains(where: { $0.id == item.id }) {
            startMultiDrag(items: selected, event: event)
        } else {
            startDrag(event: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragActive = false
    }

    private func startDrag(event: NSEvent) {
        isMultiDrag = false
        let di = NSDraggingItem(pasteboardWriter: item.pasteboardWriter)
        let sz = CGSize(width: 48, height: 48)
        // Use bounds only when it has been laid out; fall back to a safe origin.
        let origin = bounds.isEmpty
            ? NSPoint(x: 8, y: 16)
            : NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2)
        di.setDraggingFrame(NSRect(origin: origin, size: sz), contents: item.icon)
        beginDraggingSession(with: [di], event: event, source: self)
    }

    private func startMultiDrag(items: [ShelfItem], event: NSEvent) {
        isMultiDrag = true
        let sz = CGSize(width: 48, height: 48)
        let center = bounds.isEmpty
            ? NSPoint(x: 8, y: 16)
            : NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2)

        let draggingItems = items.enumerated().map { idx, shelfItem -> NSDraggingItem in
            let di = NSDraggingItem(pasteboardWriter: shelfItem.pasteboardWriter)
            let offset = CGFloat(idx) * 3
            let origin = NSPoint(x: center.x + offset, y: center.y - offset)
            di.setDraggingFrame(NSRect(origin: origin, size: sz), contents: shelfItem.icon)
            return di
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    /// Called after the drag ends — operation is .none for cancelled/rejected drags.
    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        let wasMulti = isMultiDrag
        dragActive = false
        isMultiDrag = false
        guard !operation.isEmpty else { return }

        // Destination accepted the drop → remove the dragged item(s) from the shelf.
        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                if wasMulti {
                    self?.onRemoveSelected()
                } else {
                    self?.onRemove()
                }
            }
        }
    }
}

// MARK: - Pure SwiftUI visual layer

struct ItemVisual: View {
    let item: ShelfItem
    let isHovering: Bool
    let isSelected: Bool

    @Environment(\.pixelLength) private var pixelLength

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.20) }
        return isHovering ? .white.opacity(0.14) : .white.opacity(0.07)
    }

    private var borderColor: Color {
        if isSelected { return Color.accentColor.opacity(0.80) }
        return .white.opacity(isHovering ? 0.35 : 0.12)
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.5 : pixelLength
    }

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)

            Text(item.displayName)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .scaleEffect(isHovering ? 1.05 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isHovering)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isSelected)
    }
}
