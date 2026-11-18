# Release build (Phase 7, task Q-07)

The release build is signed with your own key, which never goes into the repository. Without the key, a release build stops with an explanation; it is never signed with the debug key.

## 1. Create the release key (once)

Keep the keystore and its passwords somewhere safe, outside the repository and backed up. If it is lost, updates to an installed app can't be signed.

```bash
keytool -genkeypair -v -keystore ~/fitbuddy-release.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000
```

## 2. Point the build at it

Create `android/key.properties`; it is git-ignored.

```properties
storeFile=/home/you/fitbuddy-release.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

## 3. Register the release fingerprint with Google sign-in

Google sign-in accepts only builds signed with a fingerprint registered on an Android OAuth client. Print it:

```bash
keytool -list -v -keystore ~/fitbuddy-release.jks -alias upload
```

In Google Cloud → APIs & Services → Credentials, add an Android OAuth client for package `com.mysticstack.fitbuddy` with the release SHA-1. Keep the debug one as well.

## 4. Build

Set the version in `pubspec.yaml` (`version: 1.0.0+1`; raise the number after `+` for every build you install over an older one).

A signed APK per CPU type, the one to install on your phone (arm64 for almost all current phones):

```bash
flutter build apk --release --split-per-abi --dart-define-from-file=env/prod.json
```

A single signed APK for every CPU type (about 83 MB):

```bash
flutter build apk --release --dart-define-from-file=env/prod.json
```

An Android App Bundle, needed only if the app ever goes to Google Play:

```bash
flutter build appbundle --release --dart-define-from-file=env/prod.json
```

Outputs:
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (about 30 MB)
- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

Install:

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Check the signature:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## 5. What the release build does differently

| Item | Release |
|---|---|
| Signing | Your key from `key.properties` (APK Signature Scheme v2) |
| Code | R8 shrinking and resource shrinking; keep rules in `android/app/proguard-rules.pro` |
| Logs | Discarded (the logger's sink is off outside debug builds) |
| Backups, cleartext traffic, analytics | Off, as in debug; see `docs/privacy_audit.md` |
| FCM | No token until the app registers after sign-in, and only when Firebase values are in the env file |

## 6. Before calling a build released

1. All automated suites pass (`flutter analyze`, `flutter test`, `bash supabase/tests/run_local.sh`, and in `supabase/functions` the commands `deno check` and `deno test`).
2. The device test plan (`docs/device_test_plan.md`) passes on the phone, including section C on the release build.
3. Supabase migrations are applied and both Edge Functions are deployed (`docs/sync_and_push.md`).

## Verified in the build environment

On 18 November 2026, with a throwaway key that was deleted afterwards and never committed:
- A release build without a key stops with the message above.
- The signed APK, split APKs and AAB all build.
- `apksigner` verifies the APK.

The release build has not been run on a phone.
