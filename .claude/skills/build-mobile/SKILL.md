---
name: build-mobile
description: |
  Rebuild the flyyoung-app Flutter app after code changes — bumps the build number,
  builds the release APK and iOS IPA/archive, then opens the archive in Xcode
  Organizer so the user can distribute it manually (no App Store Connect API key
  configured on this machine, so upload itself stays a manual step). Use whenever
  the user says "rebuild", "build apk/ipa", "重新 build", or asks to test the app
  on a phone after Dart/pubspec changes in this repo.
allowed-tools: Bash, Read, Edit
---

# build-mobile

Rebuilds both mobile targets for `flyyoung-app` and stages the iOS archive for
manual distribution. Run this any time the user asks to rebuild/test the app
after code changes.

## Steps

Run every command from the repo root (`/Users/mushding_peng/Downloads/2026/flyyoung-app`).

1. **Bump the build number** in `pubspec.yaml`. Read the current `version: X.Y.Z+N`
   line and edit it to `+N+1` (keep `X.Y.Z` unless the user asked for a version
   bump too — build number alone is the norm for routine rebuilds).

2. **Fetch deps**:
   ```
   flutter pub get
   ```

3. **Build the Android APK**:
   ```
   flutter build apk --release
   ```
   Output: `build/app/outputs/flutter-apk/app-release.apk`

4. **Ensure CocoaPods is current** (only needed if `ios/Podfile.lock` might be stale —
   safe to always run, it's fast when nothing changed):
   ```
   cd ios && pod install && cd ..
   ```

5. **Build the iOS archive + IPA**:
   ```
   flutter build ipa --release
   ```
   Output: `build/ios/archive/Runner.xcarchive` and `build/ios/ipa/*.ipa`.
   Signing is already configured (`DEVELOPMENT_TEAM` in the Xcode project,
   `CODE_SIGN_STYLE = Automatic`) — this should succeed without prompting.

6. **Open the archive in Xcode Organizer** so the user can click through
   Distribute App → App Store Connect themselves:
   ```
   open -a Xcode build/ios/archive/Runner.xcarchive
   sleep 1
   osascript -e 'tell application "Xcode" to activate'
   ```

## Reporting back

Tell the user the new version/build number and both artifact paths (APK + IPA).
Remind them, only if relevant context suggests they're about to upload, that
there's no App Store Connect API key configured on this machine — actual
upload to App Store Connect requires them to sign in via Xcode Organizer or
Transporter themselves (never enter their Apple ID password on their behalf).

## Notes

- Known benign warnings to ignore/not re-investigate each time: Kotlin Gradle
  Plugin deprecation notice (mobile_scanner/nfc_manager), Swift Package Manager
  unsupported notice for the same two plugins, "Launch image is set to the
  default placeholder icon" validation warning, and a CocoaPods base-config
  note about `Pods-Runner.profile.xcconfig` (pre-existing custom Xcode config).
  None of these block the build.
- If `flutter build apk`/`ipa` fails for a *new* reason (not one of the above),
  investigate — don't just retry.
- Don't attempt `xcrun altool`/Transporter CLI upload unless the user has
  explicitly provided an App Store Connect API key (`.p8` + Key ID + Issuer ID)
  in this session or a documented location — check `~/.appstoreconnect/private_keys/`
  first either way.
