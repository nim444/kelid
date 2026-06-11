import SwiftUI

enum OnboardingStep: Int, CaseIterable, Hashable {
    case splash
    case terms
    case passphrase
    case recovery
    case touchID
    case yubiKey
}

/// First-run wizard: splash, terms, master passphrase, recovery code,
/// Touch ID, YubiKey. Back navigation stops once the master record exists —
/// the recovery code is shown exactly once and never re-displayed.
struct OnboardingView: View {
    @State private var step: OnboardingStep
    @State private var recoveryCode = ""

    init() {
        // If the app quit between creating the master and finishing onboarding,
        // resume after the recovery step instead of recreating the master.
        _step = State(initialValue: MasterKeyStore.masterExists ? .touchID : .splash)
    }

    private var canGoBack: Bool {
        step == .terms || step == .passphrase
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if canGoBack {
                    Button {
                        goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            .padding(.leading, 62) // keep clear of the traffic lights
            .frame(height: 40)

            Group {
                switch step {
                case .splash:
                    SplashStep { step = .terms }
                case .terms:
                    TermsStep { step = .passphrase }
                case .passphrase:
                    PassphraseStep { code in
                        recoveryCode = code
                        step = .recovery
                    }
                case .recovery:
                    RecoveryCodeStep(code: recoveryCode) {
                        recoveryCode = ""
                        step = .touchID
                    }
                case .touchID:
                    TouchIDStep { step = .yubiKey }
                case .yubiKey:
                    YubiKeyStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.self) { dot in
                    Circle()
                        .fill(dot == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 18)
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity)
        .kelidWindowBackground()
        .background(WindowConfigurator(hideSystemButtons: false))
    }

    private func goBack() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            step = previous
        }
    }
}
