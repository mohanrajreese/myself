# Privacy (as built)

Design: `blueprint/01-architecture.md` §5–6. Verification state is given per item.

| Protection | State | Evidence |
|---|---|---|
| Both databases encrypted at rest, separate keys | Verified by automated tests (on the build machine; same library is bundled in the APK) | `test/unit/database/encryption_test.dart` |
| Keys generated on device, kept in Keystore-backed storage, never silently replaced | Logic verified by automated tests; Keystore behaviour on the phone pending | `test/unit/database/database_key_manager_test.dart` |
| Outbox accepts only synced tables | Verified by automated tests | `test/unit/database/outbox_allowlist_test.dart` |
| Sync and network code cannot import the private database | Verified by automated tests | `test/architecture/` |
| Logger cannot write text or decimal values | Verified by automated tests | `test/unit/core/logger_test.dart` |
| Android backup and device transfer disabled; cleartext traffic disabled; analytics deactivated | Manifest verified by automated tests; `adb backup` check on the phone pending | `test/architecture/android_manifest_test.dart` |
| Meal photos encrypted per file (AES-256-GCM), stored on the phone only, index table outside the sync allow-list | Verified by automated tests; phone pending | `test/unit/nutrition/meal_photo_store_test.dart` |
| App lock, private modules, sensitive notifications | Not built (Phase 5) | — |
