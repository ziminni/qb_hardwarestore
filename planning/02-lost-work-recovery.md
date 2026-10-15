# 02 — Recover the Lost POS API Integration

**Priority: P1.** Someone already wrote the integration this project needs. It was destroyed by a merge.
Recovering it is cheaper than rewriting it.

## What was lost

Commit **`22c7c26`** ("backup") contained a working, API-backed POS catalogue:

| Path | Content |
| :--- | :--- |
| `flutter/lib/data/services/pos_service.dart` | ~80 lines. `PosService` using `ApiClient.instance` + Dio to call `/api/v1/products/` and `/api/v1/batches/`, assembling a live catalogue with FIFO stock. |
| `flutter/lib/data/repositories/pos_repository.dart` | ~10 lines. The repository wrapper. |
| `backend_django/apps/pos/{serializers,services,tests}.py` | ~17 lines of backend changes. |

None of it exists at the current tip or on `master`.

## Why it vanished

Merge **`27a853e`** ("merge: integrate frontend POS with inventory management", parents `7217199` and
`22c7c26`) resolved those paths **wholesale from the other parent**. The files were never deleted by a
human decision — a conflict was resolved the wrong way, and nobody noticed because nothing on the branch
imported the service yet.

## Recovery

Review first — this code is older than the current tip and may not compile as-is:

```bash
git show 22c7c26 -- flutter/lib/data/services/pos_service.dart
git show 22c7c26 -- flutter/lib/data/repositories/pos_repository.dart
git show 22c7c26 -- backend_django/apps/pos/
```

Restore if it looks right:

```bash
git checkout 22c7c26 -- flutter/lib/data/services/pos_service.dart
git checkout 22c7c26 -- flutter/lib/data/repositories/pos_repository.dart
```

## Caveats before assuming it still works

- It predates the port fix (`5435:5432`, backend on `8000`) and the Linux desktop work, so it was written
  against an older tree. Re-check imports and the `ApiClient` surface it uses.
- It calls `/api/v1/products/` — which is **paginated** (`PAGE_SIZE = 50`). If it read `response.data` as a
  list, it is silently broken and needs `['results']`. See `01-api-integration.md`.
- The backend `apps/pos` diff may already be superseded by later work; diff it before restoring.
- It was written alongside the invented `product.dart` model fields. If it deserialises into that model, it
  inherits the same defect.

## Why this matters

`01-api-integration.md` lists "wire products and inventory" as the P0 workstream. This commit is a
ready-made partial answer to items 1 and 2 of that plan. Recovering it — even only as reference — is worth
more than starting from a blank file.

This is also the reason the recovered file should be checked in **with a test or an import**, not just
restored: it sat unused, which is exactly how it got dropped without anyone noticing.
