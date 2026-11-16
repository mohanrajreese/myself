# Architecture (as built)

Design and rationale: [`blueprint/01-architecture.md`](blueprint/01-architecture.md). This file records what exists in the code and any deviation from the design.

## Built so far

| Area | State |
|---|---|
| Flutter project | Created at the repository root, Android only |
| Android build | AGP 9.3.1, built-in Kotlin, `compileSdk`/`targetSdk` 37, `minSdk` 29, core-library desugaring |
| SQLite | SQLite3MultipleCiphers bundled through the `sqlite3` build hook (`libsqlite3mc.so` confirmed in the debug APK) |
| Signing | Project debug keystore `android/app/debug.keystore` |

## Deviations from the blueprint

| Item | Blueprint | As built | Reason |
|---|---|---|---|
| Timezone ID | `flutter_timezone` package | Own Kotlin call through a Pigeon API | The package still applies Kotlin Gradle Plugin 1.7.10 and does not build with AGP 9 |
