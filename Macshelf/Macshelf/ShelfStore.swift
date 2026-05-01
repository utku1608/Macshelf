import Foundation
import AppKit
import SwiftUI

@Observable
final class ShelfStore {

    var items: [ShelfItem] = []

    /// Set by DropReceivingView — drives the drop-hover visual in ContentView.
    var isTargeted = false

    /// IDs of items currently in the selection set.
    var selectedIDs: Set<UUID> = []

    /// True when every item on the shelf is selected.
    var isSelectAllActive: Bool { !items.isEmpty && selectedIDs.count == items.count }

    /// Called by AppDelegate when it should respond to the shelf becoming empty.
    var onBecameEmpty: (() -> Void)?

    // MARK: - Add

    func add(urls: [URL]) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            for url in urls {
                if url.isFileURL {
                    let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
                    items.append(ShelfItem(kind: .file(url), icon: icon,
                                          displayName: url.lastPathComponent))
                } else {
                    let icon = NSImage(systemSymbolName: "link.circle.fill",
                                      accessibilityDescription: nil) ?? NSImage()
                    let name = url.host(percentEncoded: false) ?? url.absoluteString
                    items.append(ShelfItem(kind: .webURL(url), icon: icon, displayName: name))
                }
            }
        }
    }

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let icon = NSImage(systemSymbolName: "text.quote", accessibilityDescription: nil) ?? NSImage()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            items.append(ShelfItem(kind: .text(text), icon: icon,
                                   displayName: String(trimmed.prefix(48))))
        }
    }

    // MARK: - Selection

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    func clearSelection() {
        selectedIDs = []
    }

    func toggleSelectAll() {
        selectedIDs = isSelectAllActive ? [] : Set(items.map { $0.id })
    }

    // MARK: - Remove

    func remove(_ item: ShelfItem) {
        selectedIDs.remove(item.id)
        items.removeAll { $0.id == item.id }
        if items.isEmpty { onBecameEmpty?() }
    }

    func removeSelected() {
        let ids = selectedIDs
        selectedIDs = []
        items.removeAll { ids.contains($0.id) }
        if items.isEmpty { onBecameEmpty?() }
    }

    func clear() {
        selectedIDs = []
        items.removeAll()
        onBecameEmpty?()
    }
}
