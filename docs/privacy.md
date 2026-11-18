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
| Private records (habits, bowel, medication, sensitive reminders, private activities, screen time, progress photos) in the private database only; none on the sync allow-list | Verified by automated tests | `test/unit/database/private_migration_test.dart`, `test/widget/lifestyle_test.dart` |
| Private and medication notifications: generic title "Praxis reminder", secret on the lock screen, no name in any notification | Verified by automated tests; phone pending | `test/widget/lifestyle_test.dart` |
| App lock: salted PBKDF2 PIN hash, growing wait after 5 wrong PINs, every private route behind `LockGate`, digits never count as a try without Unlock | Verified by automated tests | `test/unit/security/app_lock_test.dart`, `test/widget/lifestyle_test.dart` |
| Screenshots and app-switcher preview blocked (`FLAG_SECURE`) while the lock is on; fingerprint unlock | Flag requested in tests with a fake; phone pending | `test/widget/lifestyle_test.dart` |
| Private text fields never learn from typing (no suggestions, no personalised keyboard learning) | Code review | `lib/features/private_space/presentation/` |
| Progress photos encrypted per file (AES-256-GCM), never synced | Verified by automated tests; camera on the phone pending | `lib/features/private_space/data/drift_private_repository.dart` |
| No sync request carries private data | Verified by automated tests: a full sync with private records present sends only synced tables and no private text (recording remote); the sync engine cannot import the private database | `test/widget/sync_test.dart`, `test/architecture/` |
| Push payloads hold only `{type, id}`; the phone shows fixed text by type and ignores unknown types | Verified by automated tests (app) and code review (server function) | `test/widget/sync_test.dart`, `supabase/functions/send-push` |
| Export: private data only after the PIN; optional AES-256 passphrase; saved where the user chooses, no copy kept | Verified by automated tests; save picker on the phone pending | `test/unit/export/`, `test/widget/data_test.dart` |
| Deletion: phone data (both databases, photos, notifications, app lock) and account (cloud rows and push tokens by cascade) | Verified by automated tests (app, local access-rule checks); real project pending | `test/widget/data_test.dart`, `supabase/tests/rls_checks.sql` |
