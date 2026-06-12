# Release checklist — Kelid alpha (DMG on GitHub Releases)

Same distribution model as GGTyper: ad-hoc signed DMG, not notarized, marked Pre-release.
Version lives in `MARKETING_VERSION` (both configs in project.pbxproj) — keep it in
`x.y.z` form and matching the git tag.

## 1. Build Release

In Xcode-beta: Product > Archive, or:

```sh
env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project Kelid.xcodeproj -scheme Kelid -configuration Release \
  -derivedDataPath ./build-release build
```

App lands at `build-release/Build/Products/Release/Kelid.app`.

## 2. Strip get-task-allow and re-sign

An ad-hoc Release build still carries `com.apple.security.get-task-allow` (debugger
attach), which undermines the Hardened Runtime on a secrets app. Strip it before
packaging:

```sh
APP=build-release/Build/Products/Release/Kelid.app
codesign -d --entitlements :kelid-ent.plist "$APP"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' kelid-ent.plist
codesign --force --options runtime --entitlements kelid-ent.plist -s - "$APP"
rm kelid-ent.plist
```

Verify — the output must show sandbox, hardened runtime, network client/server, USB,
user-selected files (readonly), and NO get-task-allow:

```sh
codesign -d --entitlements - "$APP"
codesign --verify --deep --strict "$APP" && echo OK
```

## 3. Fresh-user smoke test

Wipe local state and walk the full flow once on the re-signed app:

```sh
rm -rf ~/Library/Containers/com.nim444.kelid
defaults delete com.nim444.kelid 2>/dev/null; killall -u $USER cfprefsd
open "$APP"
```

Onboarding end to end, create a vault + secret, enable the MCP gateway, fetch the secret
from Claude Code, lock with Cmd+L and confirm agent behavior, check the Audit chain badge.

## 4. Package the DMG

```sh
hdiutil create -volname Kelid -srcfolder "$APP" -ov -format UDZO Kelid-<version>.dmg
```

Mount it on a clean account if possible; first launch must be right-click > Open
(ad-hoc signature).

## 5. Tag and publish

```sh
git tag v<version> && git push --tags
gh release create v<version> Kelid-<version>.dmg --prerelease --title "Kelid <version> (alpha)"
```

Release notes must state, explicitly:

- Alpha status; macOS 27, Apple silicon only.
- Ad-hoc signed, not notarized — right-click > Open on first launch.
- Interim crypto: values in the macOS Keychain, PBKDF2 verifier for the master passphrase,
  locking is policy-enforced until the crypto core ships.
- The same-UID boundary: not a sandbox against hostile processes running as your user.
- Highlights drawn from docs/MILESTONES.md.

## 6. Screenshots

3-4 for the README and release page: onboarding splash, vault + secrets view, a Guardian
verdict in the test console, the Agents pane with a live request feed.
