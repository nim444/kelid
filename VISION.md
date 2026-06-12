# Kelid — vision

*Kelid (کلید) is Persian for "key".*

Kelid is the native Swift successor of [Svault](https://github.com/nim444/Svault): a secret
access layer for cooperative AI agents, rebuilt from scratch as a first-class macOS app
instead of a Rust CLI/TUI/Tauri stack. Svault proved the model — structured requests, per-secret
policy, an AI judge for sensitive reads, and an audit trail — and its post-mortem docs (exported
in `docs/svault-export/`) are the functional baseline Kelid starts from. Svault itself is now
deprecated; Kelid is where the idea continues.

## Why rebuild, and why Swift

- Svault's desktop GUI was Tauri 2 + React over a Rust core — three stacks for one product.
  The security review and logic inventory showed most complexity lived in glue, not in the idea.
- The audience that actually uses this (people running AI agents on their Mac) expects a native
  app: Touch ID sheets, Keychain integration, menu-bar presence, Liquid Glass design — not a
  webview.
- One language end to end (Swift) for UI, daemon logic, crypto orchestration, and the MCP
  surface keeps every decision reviewable in one place.

## What Kelid keeps from Svault (the principles)

1. **Structured access.** An agent never "reads the vault" — it asks for one named secret, in a
   scope, with a truthful reason. Vague or mismatched reasons are denied generically.
2. **Policy before value.** Per-secret sensitivity tiers (low / medium / high), per-caller
   rules, time windows, rate limits, sealing after repeated denials, human-only secrets.
3. **AI judge for sensitive reads.** Medium/high requests are scored by a model against the
   stated reason before any value is returned; static tier rules are the fallback when no
   judge is available.
4. **Everything audited.** Every request — allowed or denied, human or agent — lands in an
   audit log stamped with an un-forgeable caller identity.
5. **The boundary, stated honestly.** Kelid is for cooperative and semi-trusted agents. It is
   not a sandbox against a hostile process running as your own user, and its docs and UI must
   never claim otherwise. Same-UID access is the stated limit, up front, always.
6. **MCP as the agent door.** Agents connect over MCP; humans use the app. Two paths, one
   policy engine.

## What Kelid does differently (the lessons)

- **Native security primitives first.** Master unlock backed by Touch ID and Keychain from day
  one, not bolted on. macOS biometric sheets instead of custom passphrase dialogs wherever the
  OS allows.
- **Smaller, gated command surface.** Svault's GUI grew 71 IPC commands, several ungated
  (`remove_yubikey`, `remove_touchid`, `delete_vault` without step-up auth). Kelid designs the
  gate first: every state-changing operation declares its required auth level before it gets a
  button.
- **No silent defaults on security input.** Svault parsed an unknown tier string as Low.
  Kelid rejects invalid security configuration loudly.
- **Step-by-step product build.** Like GGTyper, Kelid grows screen by screen — splash and
  onboarding first, then vault basics, then policy, judge, MCP — each step shippable and honest
  about what exists. No half-built screens.

## Source material in this repo

| Doc (`docs/svault-export/`) | What it gives Kelid |
|---|---|
| `gui-logic-inventory.md` | The complete functional spec: every behavior the old GUI had, command by command, with known gaps flagged |
| `architecture.md` | Svault's store layout, session/daemon model, crypto envelope (Argon2id + AES-256-GCM) |
| `policy-engine.md` | The full policy model: tiers, scopes, callers, windows, seals, judge thresholds |
| `security.md` | Threat model and the same-UID boundary statement Kelid inherits verbatim |
| `native-ui-options.md` | The evaluation that concluded a native Swift app is the right next form |
| `roadmap.md` | What Svault never got to — candidate material for Kelid's own roadmap |

## License posture

PolyForm Noncommercial 1.0.0: free for individuals, academia, and non-profits; commercial use
by companies is not permitted.

## Status

Pre-alpha, built milestone by milestone (Swift, SwiftUI, macOS 27 SDK, built manually in
Xcode). Onboarding, lock screen, providers, Telegram alerts, the tamper-evident audit log,
Guardian (AI judge), vaults + secrets, and the MCP agent gateway are live; the crypto core
(Argon2id keyslots, per-vault encrypted stores) is the next major engine. Every step is
logged in [docs/MILESTONES.md](docs/MILESTONES.md).
