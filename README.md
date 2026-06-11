![Swift](https://img.shields.io/badge/swift-%23FA7343.svg?style=for-the-badge&logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/mac%20os%2027-000000?style=for-the-badge&logo=apple&logoColor=F0F0F0)
![Status](https://img.shields.io/badge/status-pre--alpha-orange?style=for-the-badge)

# Kelid

**The key your AI agents have to ask for.**

Kelid (کلید, Persian for "key") is a native macOS secret access layer for cooperative AI
agents — the Swift successor of [Svault](https://github.com/nim444/Svault). An agent must say
*which* secret, in *what* scope, and *why*; policy and an AI judge decide; everything is
audited. Humans unlock with Touch ID, agents connect over MCP.

> **Status: pre-alpha, built step by step in the open.** Nothing runnable yet — the project
> starts from the splash screen and grows one verified piece at a time. See [VISION.md](VISION.md)
> for the full picture and `docs/svault-export/` for the Svault functional spec this build
> starts from.

> **The boundary, stated up front.** Kelid is for cooperative and semi-trusted agents. It is
> not a sandbox against a hostile process running as your own user — that boundary is inherited
> from Svault's threat model and stated honestly everywhere.

## Why a successor

Svault (Rust CLI + TUI + Tauri GUI) proved the model and is now deprecated. Kelid rebuilds it
as one native Swift app: Touch ID and Keychain as first-class primitives, a smaller and fully
auth-gated command surface, no silent security defaults, and a macOS-native interface instead
of a webview.

## What works today

Built step by step; every step is logged in [docs/MILESTONES.md](docs/MILESTONES.md).

- **Onboarding** — Splash → Terms → Set Passphrase → Recovery Code → Touch ID → YubiKey.
  Liquid Glass / macOS 27 styling, IBM Plex Mono, animated neutral gradient.
- **Master record** — salted iterated-SHA-256 verifier and a hashed recovery code only;
  no plaintext passphrase, recovery code, or secret on disk (interim until the crypto core).
- **YubiKey** — dependency-free native CTAP2/FIDO2 over USB HID: `getInfo`, full clientPIN v1
  (ECDH P-256, AES-CBC, pinUvAuthToken), and `makeCredential` with the `hmac-secret` extension.
- **Touch ID** — LocalAuthentication unlock check.
- **App shell** — native collapsible `NavigationSplitView` sidebar (Dashboard + a System group).
- **Settings** — searchable two-pane: change passphrase, regenerate recovery code, add/remove
  Touch ID, enroll/remove YubiKey.
- **Providers → AI Providers** — OpenRouter, OpenAI, Anthropic, AWS Bedrock, LM Studio, Ollama
  with official logos; keys stored in the macOS Keychain (never plaintext on disk), a Test
  connectivity check, and toast feedback. Communications channels are next.

Vaults, Agents, and Audit are hidden until their engines ship.

## License

**PolyForm Noncommercial 1.0.0** — free for personal, academic, and non-profit use;
commercial use is prohibited. See [LICENSE](LICENSE).
