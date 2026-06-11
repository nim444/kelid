import SwiftUI

struct AutoLockPane: View {
    @Environment(AppStore.self) private var store

    private let intervals: [(label: String, minutes: Int)] = [
        ("1 minute", 1),
        ("5 minutes", 5),
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("1 hour", 60),
        ("Never", 0),
    ]

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                icon: "timer",
                title: "Auto Lock",
                subtitle: "Kelid locks itself after a period of inactivity and on every launch. Unlocking requires your preferred method — the others stay available as fallbacks."
            )

            PaneCard {
                Text("Lock after idle")
                    .font(.kelid(12, .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $store.autoLockMinutes) {
                    ForEach(intervals, id: \.minutes) { option in
                        Text(option.label).font(.kelid(13, .regular)).tag(option.minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 220, alignment: .leading)

                if store.autoLockMinutes == 0 {
                    PaneStatus(kind: .info, message: "Auto lock is off. Kelid still locks on every launch, and you can lock manually anytime.")
                }
            }

            PaneCard {
                Text("Preferred unlock method")
                    .font(.kelid(12, .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $store.preferredUnlock) {
                    ForEach(availableMethods) { method in
                        Label(method.title, systemImage: method.icon)
                            .font(.kelid(13, .regular))
                            .tag(method)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if !store.touchIDEnrolled {
                    PaneStatus(kind: .info, message: "Enable Touch ID in Settings to use it as your unlock method.")
                }
                PaneStatus(kind: .info, message: "YubiKey unlock arrives with the crypto core, once the key actually wraps your master keyslot.")
            }

            Button {
                store.lockNow()
            } label: {
                Label("Lock Now", systemImage: "lock.fill")
                    .font(.kelid(13, .semibold))
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    private var availableMethods: [UnlockMethod] {
        store.touchIDEnrolled ? UnlockMethod.allCases : [.passphrase]
    }
}
