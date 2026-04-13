import Foundation
import AppKit
import SwiftUI

@Observable
final class ShelfStore {

    var items: [ShelfItem] = []

    /// Set by DropReceivingView — drives the drop-hover visual in ContentView.
    var isTargeted = false

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

    // MARK: - Remove

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        if items.isEmpty { onBecameEmpty?() }
    }

    func clear() {
        items.removeAll()
        onBecameEmpty?()
    }
}
