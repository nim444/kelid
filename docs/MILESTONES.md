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

## Milestone 4.4 — Release prep: docs, metadata, packaging plan (2026-06-12)

Getting ready for the first public alpha (DMG on GitHub Releases, ad-hoc
signed like GGTyper, marked Pre-release).

- **README rewritten** to match reality (it still claimed "nothing runnable
  yet" and a stale KDF): what actually works, two Mermaid diagrams
  (architecture + the full gate pipeline), install/connect instructions, an
  honest interim-crypto note, requirements (macOS 27, Apple silicon),
  credits, Required Notice.
- **VISION.md** status updated from "pre-code" to the real pre-alpha state.
- **Project metadata**: `MARKETING_VERSION` 0.1 → 0.1.0,
  `NSHumanReadableCopyright`, `LSApplicationCategoryType`
  (developer-tools). LICENSE gains the PolyForm Required Notice line.
- **docs/RELEASE.md**: step-by-step alpha checklist — Release build, strip
  `com.apple.security.get-task-allow` and re-sign with hardened runtime
  (the release audit found an ad-hoc Release build ships debugger-attach
  enabled), fresh-user smoke test, hdiutil DMG, tag + gh release, required
  release-note disclosures, screenshots.
- Repo hygiene: stray duplicate `password-svgrepo-com.svg` removed from the
  root (the real copy lives in `Kelid/AppIcon.icon/Assets/`); `.gitignore`
  gains `build-release/` and `DerivedData/`.

**Verification.** CLI build SUCCEEDED. **No wipe.**

---

## Milestone 4.3 — Pre-release hardening from a triple subagent review (2026-06-12)

Three parallel deep reviews (security, correctness, release readiness) over
the whole codebase; every CRITICAL/HIGH and the cheap MEDIUMs fixed. **No
wipe — all changes are backward compatible with existing data.**

Security fixes:

- **Secret-name enumeration closed** (`GateService`): a missing secret now
  answers with the same generic denial as a refused one — a vault-allowed
  caller can no longer probe which names exist. The "no stored value"
  operational fault also returns the generic denial (real cause
  audit-only).
- **Locked-state probing closed**: one `genericLocked` message for every
  locked state; the specific reason (never unlocked / GUI locked / vault
  window expired) goes to the audit log, and locked agent requests are now
  audited at all.
- **Judge prompt-injection framing** (`JudgeClient`): agent-controlled
  fields (`caller`, `reason`) are sanitized (control chars stripped,
  length-capped) and wrapped in data tags; the system prompt declares tag
  contents untrusted data and treats embedded instructions/verdicts as
  grounds to deny.
- **MCP HTTP parser hardened** (`McpHttp`): negative or oversized
  Content-Length rejected (was a one-request crash via index trap), 16 KiB
  header / 1 MiB body caps, malformed requests answered 400 and closed.
  Browser drive-by defense: any `Origin` header → 403; POST requires
  `Content-Type: application/json` (per MCP Streamable HTTP spec).
- **Audit chain truncation detection** (`AuditLog`): the head hash + count
  are anchored in the Keychain on every append; on load, a chain whose
  anchored head sits mid-file (tail deleted) or is missing from a non-empty
  file (log replaced) flags `chainValid = false`. A wiped container
  restarting the log stays legitimate.
- `MasterKeyStore`: PBKDF2 rounds floored at 600k on verify (a rewritten
  master.json can't lower the work factor); `SecRandomCopyBytes` result now
  precondition-checked.
- `YubiKeyService.readInfo` fails closed: undecodable getInfo no longer
  assumes hmac-secret support.
- `McpStore.noteCaller`: agent-controlled caller strings capped (64 chars,
  20 entries).

Correctness fixes:

- **Listener restart race** (`McpStore`): stale NWListener state events can
  no longer clobber the successor after a port change (identity-guarded
  handler) — this was the path to an orphaned port until app restart.
- **Decode-failure data wipe prevented**: tolerant `init(from:)` for
  `Vault`, `VaultSecret`, `Guardian`, `Seal` — adding a field in a later
  release can never make stored metadata undecodable (which previously
  reset stores to empty and orphaned Keychain values).
- **Overnight time windows** ("22:00-06:00") now wrap past midnight instead
  of never matching; window syntax is validated in the secret wizard with
  the gate's own parser (`GateService.windowValid`) — a stored-but-invalid
  window used to silently deny 24/7.
- **Vault deletion now confirms** (was a single un-confirmed click
  destroying all secrets) with a destructive confirmation dialog stating
  the secret count.
- `SecretsStore.add/update` report Keychain write failures (wizard shows
  the error, audited; a secret can no longer exist without its value);
  programmatic renames are guarded (Keychain/seal keys are name-based).
- Telegram URL building no longer force-unwraps (a hostile pasted token was
  a crash).
- Passphrase minimum unified at 10 chars (change-pane allowed 8,
  onboarding required 10).
- Finishing onboarding now opens the agent session (`lastUnlockedAt`) — MCP
  no longer says "not unlocked yet" while the freshly-onboarded human sits
  in an unlocked app.
- "Named only" agent mode requires at least one caller in the vault wizard.
- `FidoHidDevice.deinit` unregisters the input-report callback and
  unschedules from the run loop before freeing the report buffer (was a
  potential use-after-free during teardown).
- `kelid_list_vaults` honors the enable switch even if a listener lingers;
  `stop()` no longer logs audit noise when nothing was running; AuditView
  event list is lazy.

Verified correct by the reviews (no change needed): no plaintext secret
material on disk in any path; Keychain usage; PBKDF2/recovery-code
generation; policy gate ordering and seal math (no off-by-one); generic
denial discipline on the policy path; Telegram whitelist enforcement inside
`send`; loopback-only listener; CTAP2 framing/crypto; entitlements scope.

**Verification.** CLI build SUCCEEDED (Debug; Release verified by the
review agents). User test: ask an agent for a nonexistent secret name →
same generic denial as a refused one; create a secret with window
"22:00-06:00" at night → served; try deleting a vault → confirmation
dialog.

---

## Milestone 4.2 — GUI lock vs agent session split (2026-06-12)

User question: should auto-lock cut off MCP? Answer (matching Svault's
daemon-vs-TUI separation): the GUI lock is the human's; agents get their own
session.

- `AppStore.serveAgentsWhileLocked` (default ON, explicit toggle in Agents
  with audit on change) — the GUI lock screen no longer cuts agents off
  unless the user wants it to.
- `AppStore.lastUnlockedAt` — agents are **never served before the first
  human unlock** of a session (launch starts locked, so a reboot serves
  nothing until you authenticate).
- The vault wizard's auto-lock timer becomes real enforcement:
  `Vault.autoLockSeconds` (30m/12h/1d) bounds agent serving since the last
  unlock — a forgotten unlock doesn't serve forever. Expired → "vault
  auto-locked — a human must unlock Kelid again"; `kelid_list_vaults`
  reports per-vault unlocked state from the same logic.

**Verification.** CLI build SUCCEEDED. **No wipe.** User test: unlock, lock
with Cmd+L, agent request still flows (toggle on); flip the toggle off →
locked message; wait past the vault's 30m window (or set a short one) →
auto-locked message until the next unlock.

---

## Milestone 4.1 — MCP agent gateway (2026-06-12)

Agents can now actually ask. The dormant PolicyEngine goes live: Kelid runs a
local MCP server and every request is gated end to end.

**Transport.** Streamable HTTP inside the app (NWListener, loopback only,
default port 4141, configurable). The app is the daemon for now — it must be
running. `ENABLE_INCOMING_NETWORK_CONNECTIONS` added (sandbox). Minimal
HTTP/1.1 + JSON-RPC 2.0 (`initialize`, `tools/list`, `tools/call`, `ping`;
notifications → 202; GET → 405, stateless DELETE → 200). Protocol 2024-11-05.
Connect: `claude mcp add --transport http kelid http://127.0.0.1:4141/mcp`.

**Tools** (Svault's, with the user's change: **`vault` is required**):
- `kelid_list_vaults` → `[{name, unlocked, description}]`
- `kelid_get_secret(vault, name, scope, reason, caller?)`

**Security model (Svault semantics, verified against src/mcp/mod.rs).**
- Serves only unlocked state; locked Kelid → "a human must unlock"; an agent
  can never unlock.
- Human enable switch checked before any policy work; off → generic "request
  not available" (indistinguishable from a denial). Default OFF — no silent
  security defaults.
- Denials to the agent are always `GateService.genericDeny`; the real reason
  (scope mismatch, rate limit, guardian score, seal, window…) goes only to
  the audit log, stamped `[mcp]`.
- `initialize` instructions describe how to ask, never the decision criteria.

**GateService — the enforced path.** Pipeline per request: app unlocked →
vault exists → vault agentMode (none = human-only; list = caller allowlist)
→ secret exists → stated scope must match → time windows (mon-fri
HH:MM-HH:MM parser, start-inclusive end-exclusive) → PolicyEngine (seal →
reason ≥10 → required callers → per-secret rate limit → bursts → tier) →
guardian via the vault's assigned guardian (medium fails open flagged, high
fails closed). Auto-seal at 5 denials/300s; **a Telegram alert fires to all
whitelisted chats when a secret seals**. Activity window persisted in
gate-state.json (0600). Agent grants stamp lastReadAt.

**Agents section unhidden.** Gateway card (enable switch, running status,
port + apply), connect snippet with copy, callers-seen chips, recent agent
request feed. Dashboard Agents stat = distinct callers; new `.agent` audit
category.

**Verification.** CLI build SUCCEEDED. **No wipe needed.** User test: Agents
→ enable gateway → run the claude mcp add snippet → in Claude Code ask for
DATABASE_URL (vault development-local, scope database) with a real reason →
value returned, request in the feed + audit. Vague reason → generic denial.
5 bad requests → secret seals + Telegram alert. Lock Kelid (Cmd+L) → agent
gets "a human must unlock".

---

## Milestone 4.0 — secrets inside vaults (2026-06-12)

Vaults now hold secrets — Svault's Secrets screen ported, with Kelid's
per-secret rate limit and seal controls. Next: daemon + MCP gateway, where
the dormant PolicyEngine goes live against these secrets.

**Storage (no-plaintext rule honored).** Secret VALUES live in the macOS
Keychain — one entry per secret (`vault.<vaultID>.<name>`, OS-encrypted,
ThisDeviceOnly), the same mechanism as provider keys. Only metadata
(name, scope, tier, flags, rate limit, callers, windows) is in the registry.
The crypto core later migrates values into the vault's own AES-256-GCM
store. No secret value ever touches disk unencrypted.

- `Models/VaultSecret.swift` — name, scope, tier, requireReason, description,
  requiredCallers, timeWindows, **per-secret rateLimit**, lastReadAt.
- `Services/SecretsStore.swift` — secrets per vault (UserDefaults metadata),
  values via KeychainStore, seals in `secrets-state.json` (0600). Vault
  deletion sweeps its Keychain entries and seals.
- `Views/Vaults/SecretWizard.swift` — Svault's 2-step wizard: **Secret**
  (name locked on edit, value SecureField with "unchanged" placeholder on
  edit + reveal toggle, scope) → **Access rules** (tier radio cards with the
  no-guardian warning, "Always ask the guardian — even at low tier",
  description, **rate limit** stepper defaulted from the vault, allowed
  callers, time windows). Svault's hint texts carried over.
- `Views/Vaults/SecretsView.swift` — per-vault secret cards (scope/tier/
  sealed/always-judged badges, rate + callers + window + last-read line),
  actions: **Reveal** (fresh Touch ID / password → audited modal with
  concealed-clipboard Copy), Edit, **Seal** (manual panic button — every
  request denies until unsealed), **Unseal** (fresh auth, denial audited),
  Delete (confirm dialog: cannot be undone).
- VaultsView: Open button → SecretsView (back chevron), secrets-count chip,
  vault delete removes its secrets. Dashboard Secrets stat live.
- New `.secret` audit category: added / updated (value replaced flagged) /
  deleted / value revealed / reveal denied / sealed / seal cleared / unseal
  denied.

**Verification.** CLI build SUCCEEDED. **No wipe needed** — additive. User
test: open vault → Add Secret (2 steps) → card shows badges; Reveal asks
Touch ID, shows value, Copy is concealed; Seal marks the card sealed; Unseal
asks Touch ID; deleting the vault removes its secrets; Audit logs the trail
and Dashboard counts update.

---

## Milestone 3.9 — Guardian is judges-only + Vaults section with wizard (2026-06-12)

User correction on 3.8: the Guardian section had grown secret rules and seals
— wrong home. Guardian now mirrors Svault's Guardian screen exactly (judges
only); vaults are where policy lives, created via **Svault's 4-step vault
wizard** (ported from `gui/src/screens/VaultConfig.tsx`).

**Guardian (restructured).**
- `GuardianView` — global switch, guardian list (default badge / edit /
  delete), creation wizard, and the test console. Nothing else.
- `GuardianTestConsole` — now a pure `svault judge test`: free fields
  (guardian, caller, secret name, scope, tier, purpose, reason) sent straight
  to the model via JudgeClient; verdict card shows the threshold math; no
  policy state is touched. Audited as "Guardian test".
- `GuardianStore` slimmed to guardian CRUD + default + global flag.
  `PolicyEngine.swift` and the `SecretRule`/`Seal` models stay as the dormant
  enforcement engine — they attach to vault secrets when the crypto core
  ships (rate limits remain per-secret by design).

**Vaults (new primary section).**
- `Models/Vault.swift` + `Services/VaultsStore.swift` — vault registry
  (metadata + policy settings, UserDefaults; the encrypted store binds to
  these entries when the crypto core lands). Name uniqueness enforced.
- `Views/Vaults/VaultWizard.swift` — Svault's exact 4 steps:
  1. **Basics** — name (vault id, locked on edit) + description ("the
     guardian reads it with every request").
  2. **Agent access** — who may ask (No agents / Named only / Any agent, with
     Svault's help texts + callers field) and the structured rate-limit input
     (count + minute/hour/day). Kelid difference: labeled **"Default rate
     limit per secret"** — enforcement is per secret, never per vault.
  3. **Protection** — tier radio cards with Svault's descriptions (plus the
     "human-only while no guardian is active" warning) and the guardian
     choice: "Guardian reviews requests (recommended)" with an assigned-
     guardian picker (default-guardian fallback) vs "Policies only"; honest
     warning block when no guardian exists.
  4. **Locking** — auto-lock toggle + 30m/12h/1d timer, unlock method
     (Passphrase / YubiKey with not-enrolled hint).
- `Views/Vaults/VaultsView.swift` — vault cards with tier / guardian /
  agent-mode / per-secret-rate chips, edit (same wizard prefilled, name
  locked) and delete. Dashboard "Vaults" stat is now live.
- Sidebar: Dashboard, Vaults, Guardian, Audit. Vault create/update/delete
  audited.

**Verification.** CLI build SUCCEEDED. **No wipe needed** — additive
(orphaned `guardian_rules`/`guardian-state.json` from 3.8 are ignored
harmlessly). User test: Guardian shows judges only; create a vault through
the 4 steps and assign the guardian; card chips reflect choices; edit reopens
prefilled with the name locked; audit logs the lifecycle.

---

## Milestone 3.8 — Guardian: AI judge + secret-level policy engine (2026-06-12)

The Guardian (Svault 2.0's name for the AI judge) arrives as a working,
testable subsystem ahead of the vault engine. **Kelid's deliberate change vs
Svault: rate limiting and brute-force protection live on the secret, not the
vault** — every limit, burst ceiling, and seal is a property of the individual
secret, counted across all callers so rotating caller names doesn't help.

- `Models/GuardianModels.swift` — `Tier` (low/medium/high), `Guardian`
  (provider ref + model + allow/high thresholds + criteria; API key stays in
  the provider's Keychain entry), `SecretRule` (scope, tier, requireReason,
  purpose, **per-secret rateLimit** "5/hour", requiredCallers), `Seal`.
- `Services/PolicyEngine.swift` — pure pipeline in Svault's gate order:
  sealed → reason ≥10 chars → required callers → per-secret rate limit →
  per-caller burst (5/10s) → per-secret burst (10/10s) → tier gate. Svault
  constants: seal at 5 denials/300s (medium/high only, any caller).
- `Services/JudgeClient.swift` — Svault's judge prompt verbatim (JSON-only
  verdict, 0–100 score); OpenAI-shaped chat completions (OpenRouter, OpenAI,
  LM Studio, Ollama via /v1) + native Anthropic messages API; 6s cloud /
  120s local timeouts; lenient JSON verdict extraction; `listModels` for the
  wizard. No secret values ever appear in prompts.
- `Services/GuardianStore.swift` — guardians/rules/flags in UserDefaults
  (no secrets), seals + activity window in `guardian-state.json` (0600) so
  seals survive restarts. `evaluate(...)` runs gates, calls the judge for
  medium/high (or low + requireReason), applies thresholds (high tier uses
  highThreshold), Svault failure semantics (medium fail-open flagged, high
  fail-closed), records activity, triggers seals, audits everything.
  `unseal` clears the seal + its denial window (else it would instantly
  re-seal).
- `Views/Guardian/GuardianWizard.swift` — Svault's exact 3-step wizard:
  1) Provider (configured ones only, logos, honest empty state), 2) Model
  (live list, "(recommended)" pre-selected — gemini-2.5-flash on OpenRouter —
  free-text fallback), 3) Tuning (name, allow 60 / high 80 steppers,
  criteria). First guardian flips the global switch on. Plus
  `RuleEditorSheet` for per-secret rules with rate-limit format validation.
- `Views/Guardian/GuardianTestConsole.swift` — `svault judge test` as GUI:
  pick rule + caller + stated reason → runs the REAL pipeline → ALLOW/DENY
  verdict card with 0–100 score gauge, rationale, and a SECRET SEALED badge
  when a denial trips the threshold.
- `Views/Guardian/GuardianView.swift` — status card (operational check:
  global switch + provider credential), guardian cards (default badge, edit,
  delete), Secret Rules list (tier chips, SEALED marker), Sealed Secrets card
  with human-only **Unseal** (fresh Touch ID / password, mirroring Svault's
  fresh-credential rule; denial audited).
- Sidebar: Guardian between Dashboard and Audit. New `.guardian` audit
  category: guardian created/updated/deleted, request allowed/denied (with
  score), secret sealed, seal cleared, unseal denied.

**Verification.** CLI build SUCCEEDED. **No wipe needed** — additive. User
test: wizard with OpenRouter → rule DB_URL (medium, 3/hour) → good reason
allows with score, vague reason denies, 5 denials seal it, unseal via Touch
ID, rate limit trips on the 4th allowed read in an hour; Audit shows the
whole trail.

---

## Milestone 3.7 — tamper-evident audit log + Audit section (2026-06-12)

"Everything is audited" becomes real: an append-only, hash-chained audit log
and a charts-backed Audit section in the sidebar.

- `Services/AuditLog.swift` — `AuditEvent` (category, action, detail, outcome)
  in a **tamper-evident hash chain**: each entry's SHA-256 covers the previous
  entry's hash, so editing or deleting any line in `audit.jsonl` breaks
  verification for everything after it. JSONL on disk (0600, sandbox
  container), chain verified on every load, `chainValid` surfaced in the UI.
  **Details never contain secret values** — names and outcomes only.
  Recording never throws into the caller: auditing must not crash the app.
- `Views/Audit/AuditView.swift` — stat cards (Total / Today / Failures+Denied /
  **Hash Chain Verified-or-BROKEN**), a 14-day **daily activity bar chart**
  (native Swift Charts, brand gradient), category filter menu + search, and
  the event stream with outcome chips (ok / failed / denied / info) and
  relative timestamps.
- Audit unhidden in the sidebar (Dashboard + Audit primary). The Dashboard
  "Audit Events" card now shows the live count.

**Instrumented (init audit logic — everything built so far).**
Session: unlock via Touch ID / passphrase, failed unlocks, manual lock,
auto-lock (with idle minutes). Master: passphrase created / changed / change
failed, recovery code regenerated / failed. Touch ID: enabled / failed /
removed. YubiKey: enrolled / enrollment failed / removed. AI providers: key
saved / removed / revealed / **reveal denied** / test passed / test failed /
endpoint saved. Telegram: token saved / removed / revealed / reveal denied,
bot verified / failed, chat whitelisted (discovery + manual) / removed, test
message sent / failed. System: onboarding completed.

**Verification.** CLI build SUCCEEDED. **No wipe needed** — additive. User
test: use the app a bit, open Audit, watch events stream in, filter and
search, check the chart populates today's bar, confirm "Hash Chain Verified".

---

## Milestone 3.6 — Telegram alert channel with whitelist (2026-06-12)

First Communications provider: a Telegram bot for audit alerts and (later)
approvals. Security model adapted from **OpenClaw's** channel design
(docs.openclaw.ai/channels/telegram): default-deny allowlist, pairing-style
approval for unknown senders, long polling (a desktop app has no public
webhook endpoint), groups as negative chat IDs.

- `Services/TelegramService.swift` — Bot API client (ephemeral URLSession):
  `getMe` (token validation), `discoverChats` (getUpdates → distinct chats,
  discovery only), `send`. **The whitelist check lives inside `send()`** — a
  non-whitelisted chat ID throws `notWhitelisted`; no caller can bypass it.
- `Services/TelegramStore.swift` — bot token in the **Keychain**
  (`comms.telegram.bot_token`); whitelist (chat id + title + kind — not
  secrets) in UserDefaults; discovered-pending chats in memory only.
- `Views/Providers/TelegramPane.swift` — token card (same gated-reveal
  pattern: Touch ID to reveal, field clears after save, Test → "Connected as
  @bot"), whitelist card: approved chat rows (send-test paperplane + remove),
  **Find New Chats** (message the bot → appears as pending → explicit
  Approve), manual chat-ID entry (negative = group).
- Communications category now lists Telegram (live, official logo) and Resend
  (coming soon). `TelegramStore` injected app-wide for the future audit/alert
  engine.

**Verification.** CLI build SUCCEEDED. **No wipe needed** — additive. User
test: save BotFather token → Test → message the bot in Telegram → Find New
Chats → Approve → paperplane sends "Kelid test message".

---

## Milestone 3.5 — auto lock + lock screen (2026-06-11)

**Session locking.** Kelid now locks itself when idle and on every launch.

- `AppStore` gains `isLocked`, `autoLockMinutes` (default **5**, options
  1/5/15/30/60/Never), `preferredUnlock` (Touch ID / Passphrase), an
  `NSEvent.addLocalMonitorForEvents` activity monitor plus a 5s idle check
  timer, and `lockNow()` / `unlock()`. **Launches locked** whenever onboarding
  is complete — a secrets app authenticates on every start.
- `LockScreenView.swift` — full-window lock UI over the animated mesh: Kelid
  glyph in glass, preferred method primary, the other as a fallback link.
  Touch ID never auto-prompts (user feedback: the popup on appear was
  annoying) — the sensor sheet only opens after clicking the unlock button.
  Passphrase verifies against the PBKDF2 record and clears from state after
  each attempt. While locked, RootView renders **only** the lock screen — no
  app content exists underneath.
- `Settings > Auto Lock` (searchable: lock/idle/timeout/session/timer) —
  interval picker, preferred-method radio group (Touch ID hidden until
  enrolled), honest note that YubiKey unlock arrives with the crypto core,
  and a Lock Now button.
- Toolbar lock button (Cmd+L) next to the status chips.

**Placeholders.** Unlock is still gate-based (verify/biometric check), not a
keyslot decryption — that binding lands with the crypto core. YubiKey cannot
truly unlock until hmac-secret wraps the master keyslot.

**Verification.** CLI build SUCCEEDED. **No wipe needed** — additive defaults
only. User test: launch → lock screen; unlock; idle 5 min → relocks; Cmd+L /
Lock Now → instant lock; preferred method switch reorders the lock screen.

---

## Milestone 3.4 — maximum-hardening pass (2026-06-11)

User call: close every gap that can be closed natively before moving on. Wipe
approved, so no legacy compatibility kept.

**KDF upgraded.** Master verifier is now **PBKDF2-HMAC-SHA256, 600,000 rounds**
(OWASP 2023 recommendation) via CommonCrypto's vetted implementation — replaces
the interim naive iterated SHA-256. Salt widened 16 → 32 bytes. `master.json`
gains a `kdf` field; `verify` refuses records whose kdf does not match (no
silent legacy path). Argon2id remains a crypto-core candidate via a vetted
library — hand-rolling it was rejected on principle.

**Hardened Runtime enabled** (both configs) — blocks DYLD injection, unsigned
library loading, and debugger attachment in release builds.

**Provider key reveal gated.** The stored API key is no longer auto-loaded into
view state when the pane opens. The field stays empty ("Saved — type to
replace, or reveal"); revealing the saved key requires **Touch ID or the Mac
password** (`LAPolicy.deviceOwnerAuthentication` via
`TouchIDService.requireUserPresence`). After Save the field clears; hiding a
revealed key drops it from state. Test falls back to the stored key
transiently without displaying it.

**Memory hygiene (best effort within Swift).**
- CtapPinProtocol zeroes the ECDH shared secret + PIN hash buffers on exit.
- YubiKey PIN fields cleared after successful enrollment (onboarding + Settings).
- Recovery-code pane clears the passphrase immediately after use.
- ChangePassphrase already cleared its fields; PassphraseStep state dies with
  the view.

**Misc.** Recovery code now uses rejection sampling (zero modulo bias). Data
directory forced to 0700 in both write paths (master + yubikey records).

**Deliberate non-changes.** `NSWindow.sharingType = .none` (screenshot
exclusion) was considered and skipped — it would also block the user's own
dev screenshots; candidate for a later "screen privacy" toggle. In-app
verify rate-limiting skipped as theater: a same-UID attacker brute-forces
`master.json` offline anyway; the 600k-round KDF is the real defense.

**Verification.** CLI build SUCCEEDED. **Wiped** (user-approved): container
data + defaults gone, cfprefsd flushed. The OpenRouter key remains in the
Keychain (encrypted, still valid). Fresh onboarding required.

---

## Milestone 3.3 — deep security audit of the unlock path (2026-06-11)

Full review of every file in the passphrase / recovery / Touch ID / YubiKey /
provider-key path, plus inspection of every artifact actually persisted on disk.

**Verified clean.**
- `master.json` (0600): salt + iterated-SHA-256 verifier + recovery-code hash
  only — all one-way, nothing reversible.
- `yubikey.json` (0600): credential ID + AAGUID + rpID — public values by FIDO
  design, not secrets.
- UserDefaults: booleans, window frames, provider `{enabled, baseURL}` — decoded
  the actual plist blob to confirm no key material.
- Provider API keys: Keychain only (`WhenUnlockedThisDeviceOnly`, no iCloud
  sync); confirmed via `security find-generic-password`.
- No `print`/`NSLog`/`os_log` anywhere — no secret can leak into logs.
- Passphrase: SecureField → create/verify only; constant-time verifier compare.
- CTAP2 PIN: never crosses USB in plaintext — LEFT16(SHA-256(pin)) encrypted
  with AES-256-CBC under the ECDH(P-256) shared secret per clientPIN v1;
  pinUvAuthToken lives only in memory.
- Recovery code: SecRandomCopyBytes, shown once, onboarding @State cleared on
  Continue.
- Sandbox on; entitlements limited to USB + outgoing network.

**Hardenings applied.**
- Recovery-code copy now sets `org.nspasteboard.ConcealedType` (onboarding +
  Settings) so clipboard managers do not archive the code.
- `AIProviderClient` uses an **ephemeral URLSession** — no disk cache or cookies
  from authenticated test requests.

**Known interim gaps (documented, by design until the crypto core).**
- Verifier KDF is iterated SHA-256 (120k), not Argon2id yet.
- Touch ID is a verified UI gate, not a cryptographic keyslot binding.
- YubiKey credential enrolled but hmac-secret does not wrap anything yet.
- Swift cannot deterministically zero String memory (platform limitation).
- Provider key "reveal" has no re-auth gate yet (candidate: Touch ID before
  reveal). The same-UID boundary remains as stated everywhere.
- Recovery-code alphabet sampling has a negligible modulo bias — switch to
  rejection sampling in the crypto core milestone.

**Verification.** CLI build SUCCEEDED. **No wipe.**

---

## Milestone 3.2 — AI Providers UX polish (2026-06-11)

**Feedback addressed.**
- **Official brand logos.** Downloaded the real monochrome marks (OpenRouter,
  OpenAI, Anthropic, AWS, LM Studio, Ollama) from simple-icons into
  `Assets.xcassets/*Logo.imageset` (template-rendered, vector-preserving), tinted
  with the brand gradient. `ProviderLogo.swift` renders them with an SF Symbol
  fallback. Used in the provider list and pane header. SF Symbols removed from
  provider display.
- **Consistent buttons.** Reworked the action row into one `buttonRow` with a
  single `.controlSize(.large)` + `.buttonBorderShape(.capsule)` applied to all
  buttons — no more per-button manual padding making one taller than the next.
  Save (prominent) / Test (glass) / Remove (glass destructive) now match.
- **Test button + toast.** New `AIProviderClient.test(...)` does a cheap
  authenticated GET per provider (OpenRouter `/key`, OpenAI/Anthropic `/models`,
  LM Studio `/models`, Ollama `/api/tags`; AWS reports "unsupported until the
  request engine"). Result shows as an auto-fading toast (`Toast.swift`,
  `.toast($binding)` modifier — bottom capsule, ~1.6s fade).

**Verification.** CLI build SUCCEEDED. Network entitlement already on. **No wipe.**

---

## Milestone 3.1 — sidebar cleanup + AI Providers (2026-06-11)

**Sidebar fixes (user feedback).**
- Removed the **duplicate** sidebar toggle — the custom button in the pane
  toolbar is gone; only the native macOS `NavigationSplitView` toggle remains.
- Removed the "Kelid" brand label from the sidebar top (now just clears the
  traffic lights).
- **Hid Vaults / Agents / Audit** from the sidebar — they require onboarding
  that hasn't shipped. `MainSection` is now `dashboard / providers / settings`.

**Providers (new System section, above Settings).** `Views/Providers/`.
- `ProvidersView.swift` — a segmented switch (AI Providers / Communications)
  over a two-pane layout. Communications is a `ComingSoon` placeholder (Telegram,
  Resend, etc. for outbound notifications).
- `AIProviderPane.swift` — per-provider config. Cloud providers (OpenRouter,
  OpenAI, Anthropic, AWS Bedrock) take an API key with reveal toggle + remove;
  local runtimes (LM Studio, Ollama) take a base URL. Configured/not-configured
  status badge.
- `Models/AIProvider.swift` — provider catalog (name, icon, auth kind, key hint,
  default local URL, summary, keychain account).
- `Services/ProvidersStore.swift` — `@Observable`; non-secret config (enabled,
  baseURL) in UserDefaults, **secrets in the Keychain**.
- `Services/KeychainStore.swift` — generic Keychain get/set/delete, service
  `com.nim444.kelid`, `WhenUnlockedThisDeviceOnly`.

**Secret storage decision.** AI provider API keys are real secrets but the vault
engine isn't built yet. Rather than write them to disk, they go in the **macOS
Keychain** (OS-encrypted) — consistent with Kelid's Keychain-first principle. No
plaintext provider key ever touches disk. When the crypto core lands these can
migrate into a Kelid vault.

`ComingSoonPane(section:)` was generalized to `ComingSoon(icon:title:message:)`.

**Verification.** CLI build SUCCEEDED. **No wipe needed** — additive.

---

## Milestone 3 — native sidebar shell + Settings (2026-06-11)

**What shipped.** The post-onboarding app is now a native `NavigationSplitView`
shell instead of a single dashboard screen.

- `MainWindowView.swift` — collapsible sidebar (Dashboard / Vaults / Agents /
  Audit, plus a System section with Settings). An always-visible toggle button
  (`sidebar.leading`) in the detail top bar collapses/restores the sidebar with
  animation; when collapsed it shifts clear of the traffic lights. Brand mark
  pinned to the sidebar top via `safeAreaInset`. Status chips (Touch ID / YubiKey)
  on the right.
- `DashboardView.swift` — refactored into `DashboardPane` (content only; chrome
  now lives in the shell) plus a generic `ComingSoonPane` for Vaults/Agents/Audit.
- `Settings/SettingsView.swift` — a self-contained two-pane Settings screen with
  a **searchable** item list (filters on title + keywords) and a detail pane.
  Items: Change Passphrase, Recovery Code, Touch ID, YubiKey.
- `Settings/SettingsPaneKit.swift` — shared `PaneHeader`, `PaneCard`, `PaneStatus`.
- `Settings/ChangePassphrasePane.swift` — verify current → re-derive verifier
  under a fresh salt → rewrite `master.json`. Recovery hash untouched.
- `Settings/RecoveryCodePane.swift` — **honest design**: the recovery code was
  only ever stored as a hash, so it cannot be "revealed". Confirm passphrase →
  mint a new code (old one stops working) → show once with copy.
- `Settings/TouchIDPane.swift` — add (LocalAuthentication check) / remove.
- `Settings/YubiKeyPane.swift` — presence polling, PIN field + "no PIN" hatch,
  enroll / remove (same CTAP2 path as onboarding).

**MasterKeyStore additions.** `changePassphrase(current:new:)` and
`regenerateRecoveryCode(currentPassphrase:)`, plus `MasterError.notFound` /
`.wrongPassphrase` and private `loadRecord()` / `write()`. No change to the
`master.json` format — purely additive.

**Decisions.** Settings uses a custom HStack two-pane (not a nested
NavigationSplitView) to keep the IBM Plex Mono / glass aesthetic and a working
search filter. "Reveal recovery code" was reinterpreted as "regenerate" because
the plaintext is never stored — surfaced to the user rather than faked.

**Placeholders.** Vaults/Agents/Audit are empty states. Touch ID still records a
verified biometric check, not yet a keyslot binding. Settings does not yet require
re-auth to *open* (only mutations verify the passphrase).

**Verification.** CLI build SUCCEEDED. User to build/run in Xcode and exercise the
sidebar toggle + each Settings pane.

**Wipe.** Not needed — additive only, `master.json` format unchanged. Existing
onboarding data stays valid.

---

## Milestone 2.8 — fix attestation parse + on-disk data audit (2026-06-11)

**Bug fixed.** PIN enrollment got past the handshake but failed with "no authData
in attestation". Cause: the CTAP2 makeCredential response keys `authData` at map
key **0x02** (0x01 is `fmt`, a string), but `parseCredentialID` read 0x01. Changed
to 0x02. PIN flow + credential parse should now complete.

**Security audit (user asked: any unencrypted data on disk?).** Inspected the
sandbox container. Only file written is `master.json`, containing exclusively
one-way material: a random salt, a salted-iterated SHA-256 **verifier** (not the
passphrase — irreversible), a SHA-256 **hash of the recovery code** (not the
code), plus iterations/timestamp. No plaintext passphrase, recovery code, or
secret anywhere. Kelid stores **no user secrets yet** (no vaults), so there's
nothing that should be encrypted-but-isn't. Password verifiers are stored as
hashes by design. Real secret encryption (AES-256-GCM under a passphrase-derived
key) arrives with the crypto core.

**Wipe.** Done — container swept, zero data files remain.

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
