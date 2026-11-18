---
name: adding-android-capability
description: Use when Praxis work needs an Android permission, Kotlin plugin, Pigeon API, foreground service, broadcast receiver, WorkManager job, sensor, alarm or system setting, or when native behaviour differs between Android versions or phone makers.
---

# Adding an Android capability

Native features fail quietly and differently per Android version. Keep Kotlin thin, gate by version, and never call a hardware feature verified from the cloud environment.

## Steps

1. **Check the plan.** Permission and component tables: `docs/blueprint/01-architecture.md` §2.1–2.3. Plugin list: `02-dependencies.md` §4. Do not add a permission outside those tables without asking.
2. **Declare the API** in `pigeons/<plugin>.dart`; regenerate. Dart wrapper returns `Result<T, Failure>` and maps every platform error to `PlatformFailure` or `PermissionFailure`.
3. **Split the logic.** Kotlin: read the sensor or system service and return raw facts. Dart: decisions, calculation, scheduling. Pure Dart gets unit tests; Kotlin helpers get JVM tests under `android/app/src/test`.
4. **Gate by version.** The phone is Android 10 (API 29); target is API 37. Wrap anything newer in an `SDK_INT` check and give the older path explicit behaviour.
5. **Permission flow.** Rationale sheet → system prompt or settings page → re-check on return. Cover: granted, denied, denied permanently, revoked later.
6. **Manifest.** Add the permission, component and `foregroundServiceType`; extend the manifest test.
7. **Failure states in the UI.** Unsupported device, permission missing, capability denied, interrupted by the system. Use the limitation wording in `04-ui-ux-spec.md` §7; never promise delivery or accuracy.
8. **Device test.** Add or update the numbered case in `docs/device_test_plan.md` with exact steps and expected result.
9. **Status.** Mark the task ⏳ and add a row to the device backlog in `docs/implementation_status.md`.

## Version gates to remember

| Feature | API 29 | Newer |
|---|---|---|
| `POST_NOTIFICATIONS` | implicit | prompt from 33 |
| Exact alarms | allowed | special access from 31, off by default from 34 |
| Foreground-service type | optional | required from 34 |
| Starting a service from the background | allowed | restricted from 31 |
| Full-screen intent | manifest | special access from 34 |

## Never

- Open a Drift database or read an encryption key from Kotlin.
- Write `MethodChannel("...")` by hand.
- Report "works" for anything involving a sensor, alarm, service, reboot or battery manager without a device result.
