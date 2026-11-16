---
paths:
  - "android/**"
  - "pigeons/**"
  - "lib/core/platform/**"
  - "lib/core/permissions/**"
---

# Android native rules

- `minSdk 29`, `compileSdk`/`targetSdk 37`. Gate every newer API at run time (`Build.VERSION.SDK_INT`); table in `docs/blueprint/01-architecture.md` §2.2.
- Platform channels are declared in `pigeons/` and generated. No hand-written `MethodChannel` strings.
- Kotlin stays thin: sensor, system services, receivers. Calculation and policy live in pure Dart where they can be unit-tested.
- Native step code writes only to the native step buffer. It never opens a Drift database or reads an encryption key.
- Ask for a permission in context, after a rationale sheet, never at first launch. Handle denial and later revocation.
- Do not declare `USE_EXACT_ALARM`, `ACCESS_BACKGROUND_LOCATION`, `CAMERA`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` or `SYSTEM_ALERT_WINDOW`.
- Backups stay disabled. Analytics collection stays deactivated.
- Anything that depends on a sensor, alarm, service, reboot or OEM behaviour is "implemented, device verification pending" until the owner runs the device test. Use the `adding-android-capability` skill.
