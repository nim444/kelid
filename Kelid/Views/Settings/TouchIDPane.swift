import SwiftUI

struct TouchIDPane: View {
    @Environment(AppStore.self) private var store
    @State private var busy = false
    @State private var status: (PaneStatus.Kind, String)?

    private var available = TouchIDService.isAvailable

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                icon: "touchid",
                title: "Touch ID",
                subtitle: "Unlock Kelid with your fingerprint. A later milestone binds Touch ID to a keyslot that wraps your master key; today it records a verified biometric check."
            )

            PaneCard {
                if !available {
                    PaneStatus(kind: .info, message: "This Mac has no Touch ID sensor available to Kelid.")
                } else if store.touchIDEnrolled {
                    PaneStatus(kind: .success, message: "Touch ID is enabled for this vault.")
                    Button("Remove Touch ID", role: .destructive) {
                        store.touchIDEnrolled = false
                        status = (.info, "Touch ID removed.")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .disabled(busy)
                } else {
                    PaneStatus(kind: .info, message: "Touch ID is not set up yet.")
                    Button {
                        enroll()
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().controlSize(.small) }
                            Label(busy ? "Confirm on sensor\u{2026}" : "Add Touch ID", systemImage: "touchid")
                                .font(.kelid(14, .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(busy)
                }
            }

            if let status {
                PaneStatus(kind: status.0, message: status.1)
            }
        }
    }

    private func enroll() {
        busy = true
        status = nil
        Task {
            let ok = await TouchIDService.authenticate(reason: "Enable Touch ID for Kelid")
            if ok {
                store.touchIDEnrolled = true
                status = (.success, "Touch ID enabled.")
            } else {
                status = (.error, "Touch ID was not confirmed.")
            }
            busy = false
        }
    }
}
