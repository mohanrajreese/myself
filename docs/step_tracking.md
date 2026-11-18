# Step tracking (as built)

Design: `blueprint/05-notifications-alarms-steps.md` Part B. States: ☑ automated tests · 📱 on device · ⏳ device verification pending.

| Piece | Where | State |
|---|---|---|
| Sensor and permission checks, permission prompt (asked when the user turns step counting on, after an explanation) | `StepApi` (Pigeon), `StepPlugin.kt`, Steps screen | ☑ (flow, with a fake) · ⏳ (sensor) |
| Native buffer: framework SQLite `step_buffer.db`, no Flutter engine or key; boot count, elapsed time, wall time, timezone and offset per reading | `StepBufferStore.kt` | ⏳ |
| One reading when the app opens or returns | `StepService.sync` | ☑ (logic) · ⏳ |
| Snapshot job about every 15 minutes (WorkManager; Android may delay it) | `StepSnapshotWorker.kt` | ⏳ |
| Opt-in continuous counting: foreground service (type `health`), batched listener, a reading every 5 minutes when steps change, at midnight, shutdown, and timezone or clock change; silent ongoing notification | `StepCollectionService.kt`, Steps → Continuous counting | ⏳ |
| Reading at boot or app update; service restarted if continuous counting is on | `SystemEventReceiver.kt` | ⏳ |
| Attribution: first reading is a baseline; same-boot differences; reboot gaps; backwards counter and implausible rates marked uncertain; midnight split by time, uncertain when the span is over 10 minutes; each period uses the offset recorded with its reading | `StepAttributionEngine` | ☑ (10 tests) |
| Ingest: readings stored, affected days recomputed, raw readings kept 60 days | `DriftStepRepository` | ☑ |
| Daily totals: sensor count plus the user's labelled adjustment; one synced `step_logs` row per day; raw readings never sync | `local_step_daily`, `step_logs` | ☑ |
| Dashboard: today, goal, percentage, remaining, 7-day average, change against last month, week and month charts, uncertain days explained, last reading, sensor status | Fitness → Steps | ☑ |
| No sensor: "This phone has no step counter", manual walk logging offered | Steps screen | ☑ (with a fake) · ⏳ |
| Workout steps never added to daily totals (§5.7) | `workout_sessions.steps` is informational | ☑ |

## Honest limits

Some phones count only while a listener is registered, so without continuous counting steps taken while the app is closed may be missed until the next snapshot. Battery managers can stop the service. Steps between the last reading and a sudden power-off can be lost. Nothing here is claimed as working until device tests 1–9 (`blueprint/07-testing.md` §6) pass on the owner's phone.
