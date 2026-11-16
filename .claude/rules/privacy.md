---
paths:
  - "lib/core/sync/**"
  - "lib/core/networking/**"
  - "lib/core/database/**"
  - "lib/core/notifications/**"
  - "lib/**/data/**"
  - "lib/features/{bowel,private_habits,medication,screen_time}/**"
  - "supabase/**"
---

# Privacy rules (PRD §7)

Local-only, in `PrivateDatabase` (`fitbuddy_private.db`): private habits, bowel records, private activities, sensitive reminders, medication, screen time and per-app usage, progress photos.

- Nothing under `lib/core/sync`, `lib/core/networking` or any `*_remote_source.dart` may import `private_database.dart` or a private DAO.
- `sync_outbox` accepts only tables in its allow-list. Never add a `local_` table to it. `PrivateDatabase` has no outbox.
- Supabase has no table or column for private data. Do not create one.
- Notifications from these modules: generic title, `VISIBILITY_SECRET`, opaque ID in the payload. The real text stays in the private database.
- FCM payloads carry `{type, id}` only.
- No private value, package name or free text in logs, exceptions or analytics. There is no analytics or crash SDK; do not add one.
- Private text fields disable keyboard suggestions and personalised learning.
- Any change in these paths must keep the privacy test suite green (`test/unit/privacy/`). Use the `checking-privacy-boundary` skill before committing.
