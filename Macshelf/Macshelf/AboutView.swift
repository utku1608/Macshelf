import SwiftUI
import AppKit

struct AboutView: View {

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Icon + identity ──────────────────────────────────────────────
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)

                VStack(spacing: 3) {
                    Text("Macshelf")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Version \(appVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text("A lightweight shelf for macOS — drop files, links, and text while you work, then drag them out whenever you need them.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)
            .padding(.bottom, 22)

            Divider()

            // ── Author ───────────────────────────────────────────────────────
            VStack(spacing: 8) {
                Text("by @alihaktan35")
                    .font(.system(size: 13, weight: .medium))

                VStack(spacing: 4) {
                    aboutLink("My GitHub Profile",      "https://github.com/alihaktan35")
                    aboutLink("Macshelf Repository", "https://github.com/alihaktan35/Macshelf")
                    aboutLink("Personal Website",    "https://ahsdev.com.tr")
                }
                .font(.system(size: 12))
                .focusEffectDisabled()   // no focus rings on links
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 28)

            Divider()

            // ── Copyright ────────────────────────────────────────────────────
            Text("© 2026 Ali Haktan Sığın. All rights reserved.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 14)
        }
        .frame(width: 300)
    }

    @ViewBuilder
    private func aboutLink(_ label: String, _ urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(label, destination: url)
        }
    }
}

#Preview {
    AboutView()
}
