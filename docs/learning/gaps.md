# Knowledge gaps

One line per concept I got wrong or was unsure about. Tick it when I answer it right in a later session.

- [ ] Client route guard vs server authorization: a GoRouter redirect (`AppRoutes.redirectFor` → `salesTwinOf`) silently sends a user elsewhere with no HTTP call or error code; the 403 comes only from the Django permission class (`IsUserManagerRole`) when the API is called — `flutter/lib/routes/routes.dart` (2026-11-03)
- [ ] Row-level effects of a partial release: `releasable_qty` decides each line; `release_materials` writes ONE SalesTransaction + one SalesItem per released line + ONE OfficialReceipt + ONE project-tagged CollectibleLedger + audit, bumps `released_qty`, status PARTIAL, token `is_used` stays False until every line is out — `backend_django/apps/requisitions/services.py` (2026-11-06)
- [ ] Concurrency on one token: `select_for_update` on the token row inside `transaction.atomic()` serialises two cashiers; the waiter recomputes the plan under the lock and gets `NOTHING_TO_RELEASE` or "Token has already been used."; a mid-release `INSUFFICIENT_STOCK` rolls the whole release back — `release_materials`, `tests_partial_release.py` (2026-11-06)
- [ ] Why the quantity rule lives on the server, not the till: the server is the trust boundary (stock can change between verify and confirm, other tills sell concurrently, a client can be tampered with), so the till only displays what `verify_token` computed and the server recomputes under lock at release — `services.py` vs `material_release_viewmodel.dart` (2026-11-06)
