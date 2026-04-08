import SwiftUI

/// The single screen Beamlet shows when you open the app.
///
/// Beamlet used to be a tab bar with Inbox / Send / Settings. The Inbox tab
/// (and the entire receive-side persistence model behind it) was removed in
/// favor of a notification-only receive flow — see `IncomingFileRouter`.
///
/// What this view does:
///
///   - Renders `SendView` as the main content (sending was always the
///     primary use case, now it's the only use case).
///   - Hosts the toolbar entry point to `SettingsView`.
///   - Observes `IncomingFileRouter` and presents the share sheet when an
///     incoming file is downloaded, plus a small toast banner for status.
struct MainTabView: View {
    @Environment(IncomingFileRouter.self) private var receiveRouter

    var body: some View {
        @Bindable var router = receiveRouter

        NavigationStack {
            SendView()
                .navigationTitle("Beamlet")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                                .accessibilityLabel("Settings")
                        }
                    }
                }
        }
        .sheet(item: $router.sharePresentation) { presentation in
            ShareSheet(fileURL: presentation.fileURL) {
                receiveRouter.clearShare()
            }
        }
        .overlay(alignment: .top) {
            if let toast = router.toast {
                IncomingToastView(toast: toast)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        // Auto-dismiss after a short window. Tied to the
                        // toast's id so a fast second arrival doesn't get
                        // cancelled by the prior toast's timer.
                        try? await Task.sleep(for: .seconds(2.5))
                        if receiveRouter.toast?.id == toast.id {
                            receiveRouter.clearToast()
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: router.toast?.id)
    }
}

// MARK: - Share sheet bridge

/// Thin `UIViewControllerRepresentable` wrapper around `UIActivityViewController`
/// so SwiftUI can present the system share sheet for an incoming file.
private struct ShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        vc.completionWithItemsHandler = { _, _, _, _ in
            // Fires for both success ("Save Image") and cancel — clean up
            // the temp file in either case via onComplete().
            onComplete()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Toast banner

private struct IncomingToastView: View {
    let toast: IncomingFileRouter.Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? .orange : .green)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: .rect(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}
