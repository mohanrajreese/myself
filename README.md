# Praxis

Personal Android app for daily health, fitness, nutrition, routines and digital wellbeing. Single user, local-first, encrypted on the device, with optional-by-data-type sync to Supabase.

| | |
|---|---|
| Requirements | [`docs/PRD.md`](docs/PRD.md) |
| Design and plan | [`docs/blueprint/`](docs/blueprint/README.md) |
| Progress | [`docs/implementation_status.md`](docs/implementation_status.md) |
| Agent rules | [`CLAUDE.md`](CLAUDE.md), `.claude/rules/`, `.claude/skills/` |

## Toolchain

| Tool | Version used |
|---|---|
| Flutter | 3.50.0 stable (Dart >= 3.12.0) |
| Android Gradle Plugin / Gradle | 9.3.1 / 9.5.0 |
| JDK | 17 or newer |
| Android SDK | platform 37, build-tools 37.0.0 |
| App | `com.mysticstack.fitbuddy`, minSdk 29, targetSdk 37 |

## Setup

1. Install Flutter stable and the Android SDK components above.
2. Copy `env/dev.example.json` to `env/dev.json` and fill in your Supabase URL, publishable key and Google Web client ID, and (for push) the four Firebase client values. `env/*.json` is git-ignored. Server setup for sync and push: [`docs/sync_and_push.md`](docs/sync_and_push.md).
3. Register the debug signing key with your Google Cloud Android OAuth client (package `com.mysticstack.fitbuddy`). Fingerprints are in [`docs/permissions.md`](docs/permissions.md).

```bash
flutter pub get
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

```bash
flutter analyze
```

```bash
flutter test -r failures-only
```

```bash
flutter build apk --debug --dart-define-from-file=env/dev.json
```

## Names that stay "fitbuddy"

The app is called Praxis. A few internal identifiers keep the original name on purpose, because changing them would break things already set up or installed:

| Identifier | Why it stays |
|---|---|
| Android package `com.mysticstack.fitbuddy` | Google sign-in clients and any installed copy are tied to it |
| Dart package `fitbuddy` | Internal import name only; never shown |
| Database files `fitbuddy.sqlite`, `fitbuddy_private.sqlite` and settings files | Renaming would leave existing data behind |
| Exercise ID namespace `fitbuddy.app/exercise/…` | Seeded exercise IDs are derived from it and are synced |

## Layout

Feature-first clean architecture: `lib/features/<feature>/{presentation,application,domain,data}` with shared code in `lib/core`. Native Android code is in `android/app/src/main/kotlin/com/mysticstack/fitbuddy`. Supabase SQL migrations are in `supabase/migrations`. Details: [`docs/architecture.md`](docs/architecture.md).

## Privacy

Private habits, bowel records, medication, screen time and other sensitive records are stored in a separate encrypted database and never leave the phone. See [`docs/privacy.md`](docs/privacy.md).
