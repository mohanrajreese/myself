# 08 — Technical Risk Register

Likelihood and impact: High, Medium, Low. "Device" in the last column means the mitigation can only be confirmed on a physical phone.

## 1. Android platform limitations

| ID | Risk | L | I | Mitigation | Confirmed by |
|---|---|---|---|---|---|
| R-01 | **Step sensor behaviour varies by phone.** Some devices count only while a listener is registered; batched delivery can lag; a few phones have no sensor | M | H | Foreground service keeps a listener registered; snapshot worker as fallback; unsupported-device state; manual adjustment; no accuracy claim before testing | Device |
| R-02 | **Manufacturer battery managers** (for example Xiaomi, Oppo, Vivo, Realme, Samsung, OnePlus) kill services and cancel alarms beyond stock Android behaviour | H | H | Status screen detects battery-optimisation state and links to the setting; model-specific guidance once the phone is known (D1); gaps are flagged, not hidden | Device |
| R-03 | **Foreground-service start restrictions.** Android 12+ blocks starts from the background; Android 14+ requires the `health` type and a granted permission at start | M | H | Start only from the foreground or boot; check permission first; catch the start exception and fall back to snapshots | Device |
| R-04 | **Exact alarms are denied by default** on Android 14+ | H | M | Capability check, rationale, inexact fallback with "may be delayed" label (§5.15G) | Device |
| R-05 | **Doze and battery saver delay inexact alarms** and rate-limit "while idle" alarms | H | M | Exact mode for reminders the user marks important; honest wording; overnight device test | Device |
| R-06 | **Alarms are lost on force-stop, and are not restored after reboot until first unlock.** A force-stopped app receives no broadcasts until opened | M | H | Re-plan on boot, update and app start; UI states the limitation; nothing can be done about force-stop except tell the user | Device |
| R-07 | **Alarm cap of 500 per app** | L | M | Rolling window with a budget of 400 | Unit tests |
| R-08 | **Channel settings are immutable after creation**; the user can also disable a channel | H | M | Versioned channels for sound changes; disabled-channel detection | Device |
| R-09 | **Do Not Disturb, silent mode and volume cannot be overridden** | H | L | Stated in the UI (§5.15J) | — |
| R-10 | **Full-screen alarm display** needs a special permission on Android 14+ that the user may revoke | M | L | Optional feature; heads-up notification with repeating alarm sound as the baseline | Device |
| R-11 | **Only three notification buttons**; swipe-dismiss is not reported by the plugin | H | L | Three-button layouts per reminder type; swipe treated as no action; native delete-intent as a later option | Device |
| R-12 | **Custom notification sounds** need a URI the system UI can read | M | L | Copy the file into app storage and serve it through a `FileProvider`; fall back to the default sound if playback fails | Device |
| R-13 | **Usage statistics differ from Digital Wellbeing**, events are kept only a few days, and some manufacturers restrict the API | H | M | Event-based aggregation, daily roll-up, explicit disclaimer (§5.17) | Device |
| R-14 | **Screen-time alerts are not real-time**; background checks run roughly every 15 minutes or later | H | L | Described as "may be late"; no blocking feature promised | Device |
| R-15 | **Six bottom-navigation items** exceed Material's recommended five and crowd small screens at large font sizes | M | M | Short labels; tested at 320 dp and font scale 2.0; selected-only labels at very large scales | Widget tests |
| R-16 | **GPS tracking** needs a location foreground service, drains battery, and is inaccurate indoors | M | M | Optional; manual entry never needs location; accuracy filter; while-in-use permission only | Device |
| R-17 | **Timezone and DST** affect both scheduling and day attribution | M | H | Calendar-rule scheduling; per-record timezone and offset; dedicated test cases | Unit tests, device |
| R-18 | **Shutdown broadcast is not guaranteed**, so steps just before power-off can be lost | M | L | Five-minute flush cadence bounds the loss; gap is flagged | Device |

## 2. Implementation risks

| ID | Risk | L | I | Mitigation |
|---|---|---|---|---|
| R-20 | **Toolchain churn.** AGP 9 with built-in Kotlin, `compileSdk 37` and Dart build hooks are recent; a plugin may lag | M | H | Task F-02 builds every planned plugin together before any feature work; fall back to the last compatible plugin release if one fails |
| R-21 | **Encrypted SQLite through build hooks** downloads a prebuilt binary at build time; a blocked download breaks the build | M | H | Verify in F-02 and CI; the hook supports an alternative download location; runtime cipher assertion |
| R-22 | **Key loss means data loss.** If secure storage is cleared or corrupted, both databases are unreadable. Local-only data has no cloud copy by design | L | H | Keys not bound to biometrics; clear error screen instead of silent reset; encrypted export as the user's own backup; synced data restorable from Supabase |
| R-23 | **Several isolates use the database** (UI, WorkManager, notification actions, FCM) | M | H | One shared Drift isolate, write-ahead logging, busy timeout; concurrency tests |
| R-24 | **Privacy leak through a side channel**: logs, crash reports, notification text, app switcher, backups, keyboard learning, clipboard | L | H | Five structural barriers (01 §5.1); no analytics or crash SDK; redacting logger; secret notifications; secure window flag; backups off; privacy test suite |
| R-25 | **Sync defects**: duplicates, lost updates, clock skew, account switch | M | H | Device-generated IDs and upserts; server-side stale-write trigger; server-clock cursor with overlap; explicit account binding; replay tests |
| R-26 | **Scope.** Twenty-three feature areas in one app | H | H | PRD phase order; each task ships complete or not at all; no phase starts on failing tests; status document kept current |
| R-27 | **No device in the development environment.** Hardware features cannot be verified by me | H | H | Three-state reporting (07 §9); device script per phase; Kotlin logic kept thin and unit-tested; pure-Dart engines for everything that can be pure |
| R-28 | **External accounts.** Supabase and Firebase projects are yours to create; a free-tier Supabase project can be paused after inactivity | M | M | App is local-first, so a paused or absent backend never blocks logging; sync resumes when the project is available |
| R-29 | **Database growth**: step readings, per-app usage rows, notification history | M | M | Retention rules (03 §8); indexes; pagination; query-plan checks in Phase 7 |
| R-30 | **Schema migration failure** on a phone with real data | L | H | Migration tests from every version; transactional migrations; pre-migration file copy; failure screen with export |
| R-31 | **Health-related wording** could read as diagnosis or advice | L | M | Tone rules (04 §7); insight wording test; medication dosage shown only as entered |
| R-32 | **Play Store policy**, if distribution ever changes from sideloading: usage access, exact alarms, health foreground service and health-data declarations | L | M | Out of scope for v1 (D5); permissions already limited to the minimum, which keeps a later submission possible |
| R-33 | **Photo storage** grows and adds an encryption path of its own | L | M | Downscale before encrypting; per-file keys derived from one master key; delete files with their records |
| R-35 | **Google sign-in misconfiguration.** A wrong SHA-1, package name or client ID fails with an opaque error; a debug key that changes per machine breaks sign-in | H | H | Committed project debug keystore; setup checklist with the exact fingerprints; clear on-screen error with the likely cause |
| R-36 | **Mandatory sign-in blocks first use** without internet or without Google Play services | M | M | Offline notice on the sign-in screen; after first sign-in the gate is local and never needs the network |
| R-37 | **Only an Android 10 phone is available.** Restrictions introduced in Android 12–14 cannot be device-tested | H | M | Version-gated code paths; unit tests on the gating logic; marked "not device-verified" until a newer device or emulator is used |
| R-38 | **Food dataset licence or quality.** INDB's data licence is unconfirmed and its values are recipe estimates | M | M | USDA (public domain) as the safe baseline; INDB kept out of the repository until its licence is confirmed; estimates labelled in the UI |
| R-34 | **Ephemeral cloud workspace.** Uncommitted work is lost when the session container is reclaimed | M | M | Small commits pushed to the development branch after every task |

## 3. Conflicts between the PRD and the platform

Reported as §13.1 item 9 requires.

| PRD statement | Platform reality | Resolution |
|---|---|---|
| §5.15C lists five notification actions | Three buttons maximum | Three buttons; open on tap; dismiss on swipe |
| §5.15F "custom sound selection" per reminder | Sound belongs to the channel and cannot be changed after creation | Versioned and per-sound channels |
| §5.15G "reboot recovery" | Not possible before the first unlock; not possible after force-stop | Recover at first unlock and on next app start; state the limit |
| §5.6 "dependable collection while the app is not visible" | Depends on manufacturer battery policy | Foreground service plus honest status; verified per device |
| §5.17 "optional usage alerts" | No real-time usage callback for third-party apps | Periodic check; alerts may be late |
| §3.2 six bottom destinations | Material recommends three to five | Kept as specified, with layout tests |
| §4.1 camera/photo permission explanation | System camera and photo picker need no permission | Explanation states that no permission prompt will appear |
| §2.1 "SQLCipher-compatible SQLite" | The SQLCipher Flutter package is end-of-life | SQLite3MultipleCiphers through the `sqlite3` build hook |
| §1.3 "not a calorie prescription application" | Owner decision D7 asks for targets calculated from weight | Offered as editable estimates with the rule shown and a "not medical advice" note; never applied without the user seeing them |
| §4.1 onboarding has no sign-in; §9 core features work without internet | Owner decision D2 makes Google sign-in mandatory, which needs internet once | Sign-in is step 1 of onboarding; everything after the first sign-in works offline |
