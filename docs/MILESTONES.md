# Kelid — milestone log

The running record of how Kelid is built, one verified step at a time. Each
milestone lists what shipped, the key files, decisions made, what is deliberately
still a placeholder, and how it was verified. Newest milestone on top.

Workflow: the user builds and runs manually in Xcode-beta (27.0). Claude does CLI
compile checks only (`env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project Kelid.xcodeproj -scheme Kelid -configuration Debug
-derivedDataPath ./build build`). The `Kelid/` folder is a synchronized group, so
new files appear in Xcode automatically.

Reset onboarding for testing:
`defaults delete com.nim444.kelid && rm -rf ~/Library/Application\ Support/Kelid`

---

## Milestone 2.3 — IBM Plex Mono type identity (2026-06-11)

**What shipped.** Bundled **IBM Plex Mono** (OFL, from the official IBM/plex
repo) in four weights — Regular/Medium/SemiBold/Bold — at
`Kelid/Resources/Fonts/`. `KelidFont.swift` registers them with CoreText at
launch (`CTFontManagerRegisterFontsForURL`, idempotent) and exposes
`Font.kelid(size, weight)` helpers. Registration is wired in `KelidApp.init`.
Splash title, subline, and button now use Plex Mono. (Persian "کلید" stays on
the system font — Plex Mono has no Arabic-script coverage.)

**Note.** The user asked for "the IBM font from featherbar" — featherbar actually
renders in **SF Mono**, not IBM Plex; confirmed with the user and chose IBM Plex
Mono for the monospaced technical identity. Fonts are registered at runtime
rather than via `ATSApplicationFontsPath` because the Info.plist is generated.
Synchronized group auto-copies the .ttf files into the bundle Resources.

**Wipe.** Not needed — pure UI/resources.

---

## Milestone 2.2 — splash redesign (2026-06-11)

**What shipped.** Reworked `SplashStep` for a more modern feel: larger app icon
(132pt) with a stronger accent glow; "Kelid" set in rounded 52pt bold with the
Persian "کلید" inline beside it; a single clean subline **"Secret access layer
for AI agents"**; removed the "Native successor of Svault…" line (kept that
framing for the README/VISION, not the first-run UI). The Get Started button is
now extra-large, capsule, glass-prominent with an arrow glyph and accent glow.
Added a spring fade/scale-in on appear.

**Wipe.** Not needed — pure UI.

---

## Milestone 2.1 — app icon wired (2026-06-11)

**What shipped.** The user's Icon Composer icon (`kelid.icon`) was moved into the
target group as `Kelid/AppIcon.icon` (blue auto-gradient, white password/key
glyph, neutral shadow, translucency). The placeholder `AppIcon.appiconset` was
removed to avoid a name clash; `ASSETCATALOG_COMPILER_APPICON_NAME` stays
`AppIcon`, so actool compiles it to `AppIcon.icns` + `Assets.car` automatically.
The splash screen now shows the real app icon (`NSApp.applicationIconImage`)
instead of the SF Symbol key.

**Verified.** CLI build clean; `AppIcon.icns` present in the built app bundle.
Dock icon staleness, if any, is a LaunchServices cache issue — relaunch or
`killall Dock`.

---

## Milestone 2 — real YubiKey enrollment (2026-06-11)

**Goal.** Replace the YubiKey placeholder with working hardware enrollment the
user can test with a real key.

**What shipped.**
- A native CTAP2-over-USB-HID stack in Swift (no third-party dependencies):
  - `Kelid/Services/YubiKey/CBOR.swift` — minimal canonical-CBOR encode/decode,
    scoped to CTAP2 (integer/text-keyed maps, byte/text strings, arrays, ints,
    bools). Maps are sorted by encoded-key bytes per CTAP2 canonical rules.
  - `Kelid/Services/YubiKey/FidoHidDevice.swift` — finds a FIDO device by HID
    usage page `0xF1D0` via IOKit, opens it, negotiates a CTAPHID channel
    (`INIT` with nonce), and frames CTAP2 `CBOR` commands across 64-byte reports
    (init + continuation packets, KEEPALIVE handled while waiting for the touch).
  - `Kelid/Services/YubiKey/YubiKeyService.swift` — `getInfo` to check the
    `hmac-secret` extension, then `makeCredential` (ES256, resident key, with the
    `hmac-secret` extension) on the local RP id `kelid.local`. Parses the
    credential id and AAGUID out of the attestation `authData`. Persists the
    enrollment record (credential id base64, rp id, AAGUID, timestamp) to
    `~/Library/Application Support/Kelid/yubikey.json` at mode 600.
- `Kelid/Views/Onboarding/YubiKeyStep.swift` — now live: polls key presence
  every 1.5 s, an Enroll button that runs the real flow ("Touch your key…"
  spinner), success/enrolled state with a Remove option, and honest errors
  (no key, PIN required, no hmac-secret support).
- `DashboardView` shows a "YubiKey" chip when a key is enrolled.
- Project: added `ENABLE_RESOURCE_ACCESS_USB = YES` to both build configs (the
  App Sandbox USB-device entitlement) so the HID device can be opened.

**Decisions.**
- **Raw CTAP2, not Apple WebAuthn.** `ASAuthorization` / the platform WebAuthn
  API requires an associated web domain (an `https` relying party). Kelid is a
  local vault with no web origin, so it speaks CTAPHID directly to the key —
  the same FIDO2 hmac-secret approach Svault used in Rust.
- **hmac-secret + resident key now; key derivation later.** Enrollment creates
  the credential that a future milestone will use with `getAssertion` to derive
  a hardware-backed secret. We store the credential id; we do not yet derive or
  wrap anything with it.
- **Concurrency.** The CTAP types are `nonisolated`; enrollment runs in
  `Task.detached`. This is required, not cosmetic: the HID read blocks until the
  user touches the key, so it must never run on the main actor.

**Still placeholder / not done.**
- No PIN/UV (clientPIN) protocol — keys with a PIN set are detected and the user
  is told PIN enrollment comes later, rather than failing obscurely.
- The credential is not yet used to wrap the master keyslot (that needs the
  crypto core + `getAssertion` derivation).
- Enrollment is not yet undoable from the key side (we delete only our local
  record; the resident credential stays on the key until reset).

**Verified.** CLI build clean (0 errors, 0 warnings). User confirmed milestone 1
flow; hardware enroll to be tested by the user with their own YubiKey.

**Removed.** A stray `Kelid/Services/CTAP/` stub (CBOR.swift + CTAPHID.swift)
that duplicated and collided with `Services/YubiKey/` was deleted.

---

## Milestone 1 — onboarding scaffold + dashboard (2026-06-11)

**Goal.** Stand up the app shell and the full first-run flow with Liquid Glass.

**What shipped.**
- Xcode project `Kelid.xcodeproj` (bundle id `com.nim444.kelid`, macOS 27 SDK,
  App Sandbox on, hidden title bar window, synchronized `Kelid/` group).
- `KelidApp.swift` + `RootView` — routes to onboarding or dashboard on the
  `onboarding_complete` flag.
- `Services/AppStore.swift` — `@Observable` app state (onboarding flag, Touch ID
  choice) persisted to UserDefaults.
- `Services/MasterKeyStore.swift` — creates/verifies the master passphrase record
  and issues the one-time recovery code (stores only a salted-iterated-SHA-256
  verifier + a SHA-256 hash of the recovery code, at `~/Library/Application
  Support/Kelid/master.json`, mode 600).
- `Services/TouchIDService.swift` — LocalAuthentication biometric check.
- `Views/Theme.swift` — brand gradient (accent #149CEB → teal), frosted window
  background, NSWindow configurator (hidden title bar, drag-anywhere).
- Onboarding (`Views/Onboarding/`): Splash → Terms & Agreement → Set Passphrase
  (strength meter, confirm) → Recovery Code (shown once, copy, "I saved it"
  gate) → Add Touch ID → Add YubiKey → Finish. Six progress dots; back nav stops
  once the master exists; resumes at Touch ID if quit mid-flow.
- `Views/DashboardView.swift` — Liquid Glass landing panel: glass header capsule
  + four empty-state stat cards (Vaults, Secrets, Agents, Audit Events).

**Decisions.**
- **Placeholder KDF, clearly labelled.** The passphrase verifier is iterated
  SHA-256 as a stand-in until the crypto core lands (Argon2id keyslots, vault
  DEKs wrapped under the master — see `docs/svault-export/architecture.md`).
  Nothing is presented as final crypto.
- **Honest UI.** Empty states say zero; placeholder controls say "coming soon".
  No half-built screens (per the Svault-era lesson).

**Verified.** CLI build clean; user confirmed "working as expected" except the
missing YubiKey enrollment (addressed in milestone 2).

---

## Next candidate milestones (not started)

1. **Crypto core** — Argon2id master keyslot, per-vault DEKs (AES-256-GCM),
   replace the placeholder verifier; bind Touch ID and the YubiKey credential
   as alternative keyslots that unwrap the master.
2. **Vault engine** — create/list/open vaults; the dashboard cards go live.
3. **Secrets** — add/edit/reveal with per-secret tiers (low/medium/high),
   scopes, reasons.
4. **Policy + AI judge** — port the policy model from
   `docs/svault-export/policy-engine.md`; judge sensitive reads.
5. **MCP server** — the agent door; structured `get_secret` with scope + reason.
6. **Audit log** — every request recorded; the Audit Events card goes live.
