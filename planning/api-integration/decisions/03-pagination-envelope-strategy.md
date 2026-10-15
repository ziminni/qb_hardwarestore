# Pagination Envelope Strategy

**Mode:** research · **Status:** OPEN · **Opened:** 2026-10-15

## The question

Where does handling of the `{count, next, previous, results}` envelope live, so that no repository forgets it?

## Why it matters

Every list endpoint is paginated (`PAGE_SIZE = 50`, `backend_django/config/settings.py`). The canonical
contract note is `ENDPOINTS.md` §1. A repository that reads `response.data` instead of
`response.data['results']` fails at runtime on **every** list screen — and this mistake was already published
once: `ENDPOINTS.md` claimed pagination was disabled, which is how the risk was found.

This is a cross-cutting decision: it touches every module on the map, so it belongs in Phase 0.

## Research to complete

- What does the existing `ApiClient` return today — raw `Response`, or unwrapped `data`? Read
  `flutter/lib/core/network/api_client.dart`.
- Does the auth flow (the only live path) hit any paginated endpoint, giving a precedent to follow?
- Is there an existing helper or interceptor that already unwraps envelopes?
- Do any screens need true page-by-page navigation, or is a single 50-row page sufficient for the demo? If
  `count > 50` in the seeded data for any list, that changes the answer.

## Candidate approaches

| Approach | Trade-off |
| :--- | :--- |
| Unwrap centrally in `ApiClient` | One place, impossible to forget; loses access to `count`/`next` for paginated UI. |
| Typed `Paginated<T>` wrapper returned by repositories | Explicit and type-safe; every repository must remember to use it. |
| Per-repository handling | No shared abstraction; the most likely to be forgotten. |

## Resolution

_Unresolved — needs the read of `api_client.dart` and a count check against seeded data._
