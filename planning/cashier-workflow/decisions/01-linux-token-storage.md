# Linux Token Storage

**Status:** LOCKED 2026-10-20 (user) · **Mode:** grill · **Map:** [cashier-workflow](../MAP.md)

## Question

The cashier (and every role) gets a gnome-keyring prompt on every login on Linux/WSL. How should the
client store its JWTs on Linux?

## Findings (verified in source and on the machine, 2026-10-20)

- Tokens live in `flutter/lib/core/network/api_client.dart:15-17`:
  `const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false))`.
  The only platform option set is **macOS**; it has no effect on Linux. The teammate's macOS config is
  not the cause.
- On Linux, `flutter_secure_storage_linux` 3.0.3 goes through `libsecret`
  (`~/.pub-cache/.../flutter_secure_storage_linux-3.0.3/linux/include/Secret.hpp:4`) →
  `org.freedesktop.secrets`, which on this WSLg machine is owned by `gnome-keyring-daemon` (pid 92659).
- `~/.local/share/keyrings/` holds **no keyring file** (only an empty `user.keystore`). The first token write
  after login (`saveTokens`, `api_client.dart:83-97`) makes gnome-keyring spawn its SystemPrompter to
  *create* a default keyring. Nothing unlocks one at WSL login, so the prompt comes back every run.
- Windows uses DPAPI (`flutter_secure_storage_windows-4.2.2`) and web uses browser storage: neither prompts.
- `shared_preferences` is already a dependency (`pubspec.yaml:19`) and already used by
  `lib/data/services/location_hint_store.dart:30,76`. Tests already mock secure storage with
  `FlutterSecureStorage.setMockInitialValues({})` (`test/routes/unsupported_role_routing_test.dart:277`).
- README.md:182-187 documented the symptom and both fixes, but decided neither.

## Options considered

| Option | Cost |
|---|---|
| **Linux-only `shared_preferences`** | Tokens in a plaintext prefs file on Linux machines |
| Fix the environment only (empty-password keyring) | Every new Linux machine hits the prompt once; an empty-password keyring is effectively unencrypted too |
| Demo on web / Windows only | WSL desktop keeps prompting; limits how devs and graders can run the app |

## Ruling

**Linux (non-web) stores tokens in `shared_preferences`; every other platform keeps
`flutter_secure_storage`.** macOS (teammate), Windows (DPAPI), mobile and web are unchanged.

Why: the prompt hits every Linux developer and grader, not just this machine. The environment fix only
cures one box, and it yields the same "unencrypted" security result anyway. Production hardening is
already Out of Scope in the [api-integration map](../../api-integration/MAP.md).

## Cost if wrong

Refresh tokens sit in plaintext at `~/.local/share/<app>/shared_preferences.json` on Linux. Anyone with
that user's file access can replay a session until the refresh token expires. Reversal: delete the gate;
Linux goes back to prompting.

## Build contract (for the executing session)

- One seam: a small token-store abstraction behind `ApiClient` (read/write/delete of the two existing keys
  `auth_access_token`, `auth_refresh_token`). The platform choice is **injectable**, so tests pick the store
  instead of depending on `Platform.isLinux`.
- Platform rule: `!kIsWeb && Platform.isLinux` → prefs store; else → secure store. Remember `dart:io` is
  unavailable on web: guard the import/usage so the web build still compiles.
- **RED-first tests:** (1) with the prefs store injected, `saveTokens` → `restoreTokens` round-trips both
  keys and `clearTokens` removes them; (2) the selector returns the prefs store for Linux and the
  secure store otherwise (drive it with an injected platform flag, not the host OS).
- No migration: tokens already in the keyring are simply not read; a Linux user signs in once more.
- Update README.md:182-187 in the same commit: the prompt section says it is fixed in code and why.
- **Verify live on WSL:** `flutter run -d linux`, log in as `cashier` → no keyring dialog; restart the app →
  still signed in (proves persistence, not just "no prompt").
