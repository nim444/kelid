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

## Milestone 2.7 — YubiKey PIN support (CTAP2 clientPIN) (2026-06-11)

**Goal.** The user's key has a PIN, which milestone-2 enrollment couldn't handle.
Implement the CTAP2 PIN/UV Auth Protocol so PIN-protected keys enroll.

**What shipped.**
- `Kelid/Services/YubiKey/CtapPinProtocol.swift` — PIN/UV Auth Protocol **v1**:
  ECDH P-256 key agreement with the authenticator (CryptoKit), v1 KDF
  (`sharedSecret = SHA-256(ECDH-X)`), AES-256-CBC zero-IV no-padding via
  CommonCrypto for `pinHashEnc`/token decrypt, COSE_Key encode/decode (negative
  integer keys), `getKeyAgreement` + `getPinToken` subcommands, and
  `pinUvAuthParam = LEFT16(HMAC-SHA-256(token, clientDataHash))`. Maps key status
  bytes (0x31 invalid, 0x32/0x34 blocked) to readable errors.
- `YubiKeyService` — `readInfo` now reports `clientPin` (PIN set?) + hmac-secret
  from getInfo `options`/`extensions`; `enroll(pin:)` runs the PIN handshake when
  needed and adds `pinUvAuthParam` (0x08) + `pinUvAuthProtocol` (0x09) to
  `makeCredential`. New `EnrollError.needsPIN`.
- `CBOR.Value.value(forKey:)` — lookup by signed integer key (COSE -1/-2/-3).
- `YubiKeyStep` — PIN `SecureField` + a "My key has no PIN" checkbox; **Enroll
  stays disabled until the user enters a PIN or ticks "no PIN"** (as requested).
  IBM Plex Mono throughout, capsule glass buttons.

**Limitations.** v1 only (not v2 / HKDF); no PIN-change/set flow; the token is
used for enrollment but not yet to wrap the master keyslot (crypto-core milestone).

**Wipe.** Done — wiped the sandbox container (`master.json`, `yubikey.json`,
prefs, cfprefsd flushed) so the user can test from scratch.

---

## Milestone 2.6 — neutral gradient + recovery redesign (2026-06-11)

**What shipped (feedback round).**
- **Gradient toned down + theme-aware.** `AnimatedMeshBackground` now reads
  `colorScheme`: near-black field in dark mode, near-white in light mode, with a
  single contained blue glow cell that drifts — most of the field is neutral, just
  a hint of blue (was all-blue before). Splash text/icon/button switched from
  hardcoded `.white` to `.primary`/`.secondary` so they adapt to light mode.
- **Recovery Code redesigned.** Replaced the single selected-looking code block
  with a clean 2×4 grid of monospace chips (each group in its own material tile),
  IBM Plex Mono throughout, a `.glass` Copy button, the once-only warning as a
  contained orange callout (icon + text, soft tinted box) instead of raw orange
  text, and a capsule glass-prominent Continue gated on the saved checkbox.

**Wipe.** Not needed — pure UI.

---

## Milestone 2.5 — splash: full-bleed gradient, real icon, glass button (2026-06-11)

**What shipped (feedback round).**
- **Full-bleed gradient** — moved `AnimatedMeshBackground` up to `OnboardingView`
  (behind header + content + dots) and dropped `kelidWindowBackground`, so there's
  no dark band/ring at the top; the gradient now covers the whole window
  uniformly on every onboarding step. Recolored the mesh so corners are deep blue
  (not near-black) — one cohesive field, no vignette.
- **Real icon** — extracted the user's key vector from `AppIcon.icon/Assets`
  into `Assets.xcassets/KeyGlyph.imageset` (template, vector-preserving) and use
  *that* shape (white, in a glass rounded-rect) instead of the SF Symbol.
- **Button** — switched Get Started to `.buttonStyle(.glass)`, smaller
  (controlSize large, tighter padding, 15pt), translucent glass instead of solid
  accent.

**Wipe.** Not needed — pure UI.

---

## Milestone 2.4 — splash polish: mono icon, motion, moving gradient (2026-06-11)

**What shipped.** Reworked the splash per feedback:
- **Monochrome icon** — replaced the colorful app icon with a white `key.fill`
  glyph in a glass rounded-rect, matching the IBM Plex Mono minimal aesthetic.
- **Removed** the Persian "کلید" from the splash.
- **Staggered fade-up entrance** — icon, title, subline, and button each rise
  ~26px while fading in on a short cascading delay (`StaggerModifier`, spring).
- **Moving gradient** — new `AnimatedMeshBackground` (`MeshGradient` driven by a
  `TimelineView`, control points drift on slow sine/cosine waves in the accent /
  teal range over a near-black base). Subtle, continuous motion behind content.

**Wipe.** Not needed — pure UI.

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
