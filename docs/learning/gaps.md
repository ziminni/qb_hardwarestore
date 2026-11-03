# Knowledge gaps

One line per concept I got wrong or was unsure about. Tick it when I answer it right in a later session.

- [ ] Client route guard vs server authorization: a GoRouter redirect (`AppRoutes.redirectFor` → `salesTwinOf`) silently sends a user elsewhere with no HTTP call or error code; the 403 comes only from the Django permission class (`IsUserManagerRole`) when the API is called — `flutter/lib/routes/routes.dart` (2026-11-03)
