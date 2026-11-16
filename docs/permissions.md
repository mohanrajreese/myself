# Permissions and platform setup (as built)

Plan: [`blueprint/01-architecture.md`](blueprint/01-architecture.md) §2.1. A permission is listed here when it is added to the manifest.

## Manifest permissions

| Permission | Added in | Requested when | Feature |
|---|---|---|---|
| `INTERNET` | Phase 1 | — (normal permission) | Google sign-in, Supabase |

## Debug signing key (for the Google Cloud Android OAuth client)

| | |
|---|---|
| Package | `com.mysticstack.fitbuddy` |
| Keystore | `android/app/debug.keystore` (alias `androiddebugkey`, standard debug passwords) |
| SHA-1 | `8D:7F:CD:51:E4:28:0F:61:6B:2B:53:C4:78:C7:83:5A:B1:72:DC:99` |
| SHA-256 | `D6:79:6B:53:CA:CF:FB:39:EE:16:47:DC:25:F9:3A:41:91:FE:DF:64:D5:F7:B1:4D:9C:1A:B2:DB:8D:7F:34:C1` |

This key signs debug builds only. The release key is created by the owner in Phase 7 and is never committed.
