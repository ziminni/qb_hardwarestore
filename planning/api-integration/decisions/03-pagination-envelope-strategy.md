# Pagination Envelope Strategy

**Mode:** research · **Status:** LOCKED 2026-10-16 · **Opened:** 2026-10-15

## The question

Where does handling of the `{count, next, previous, results}` envelope live, so that no repository forgets it?

## Why it matters

Every list endpoint is paginated (`PAGE_SIZE = 50`, `backend_django/config/settings.py`). The canonical
contract note is `ENDPOINTS.md` §1. A repository that reads `response.data` instead of
`response.data['results']` fails at runtime on **every** list screen — and this mistake was already published
once: `ENDPOINTS.md` claimed pagination was disabled, which is how the risk was found.

This is a cross-cutting decision: it touches every module on the map, so it belongs in Phase 0.

## Verified findings (live API + source)

All four research questions answered against the running stack and the source. Nothing guessed.

| Question | Finding |
| :--- | :--- |
| What does `ApiClient` return? | Raw `Future<Response<T>>` from `dio.get` / `dio.post`. **No unwrapping anywhere.** It exposes exactly two generic methods, `get<T>` and `post<T>`. |
| Does the one live path hit a paginated endpoint? | No. `auth` uses `/auth/login/`, `/auth/refresh/`, `/auth/logout/`, `/auth/me/` — none paginated, so there is **no precedent to copy**. |
| Is there an existing helper or interceptor? | No. The single interceptor handles JWT attach and refresh-on-401 only. |
| Do any seeded lists exceed one page? | No. Verified live — products 6, variants 8, variant-uoms 8, batches 8, categories 4, customers 3, transactions 6, ledgers 2, purchase-orders 8. **Largest is 8 against `PAGE_SIZE = 50`.** |

The envelope `{count, next, previous, results}` was confirmed live on all 9 endpoints.

The sharp consequence: **no demo screen needs page 2, but every list screen needs `.results`.** A repository
reading `response.data` throws immediately on its first call. This is not hypothetical — the canonical
contract document asserted the opposite once, which is exactly how the risk surfaced.

## Resolution — LOCKED 2026-10-16

**One unwrap helper on `ApiClient`, returning a small paged value type.**

```dart
class Paged<T> {
  const Paged({required this.items, required this.total});
  final List<T> items;
  final int total;
}
```

A single `ApiClient.getList<T>(path, fromJson, {queryParameters})` unwraps `results` and maps the items, so
the envelope is handled in exactly one place. Returning `Paged` keeps `count` available for result counts and
future paging without a second round trip.

Why not the alternatives:

- **Per-repository handling** — 27 screens each remembering `.results` is precisely the failure mode that
  produced the bad documentation. Rejected outright.
- **Unwrap inside `get<T>`** — would silently break the auth path and every non-list call, since not all
  responses are paginated. Rejected.
- **A wrapper each repository must opt into** — close to the chosen design, but putting it on `ApiClient`
  means a repository cannot accidentally bypass it.

Deferred: true page navigation. No seeded list exceeds one page, so nothing in Phases 1-6 reads `next`.
`Paged.total` is the hook a paging UI would build on if the data grows.
**Confirmed 2026-10-19 (wayfinder grill): the 40-page client cap (~2,000-row lifetime bound) stays as the
documented limit.** Graduating it to a pagination build was offered and declined — true page navigation
gets built only if real data volume nears the bound or this decision is revisited. Raising the cap
without paging was rejected with it (slower starts, same wall).
