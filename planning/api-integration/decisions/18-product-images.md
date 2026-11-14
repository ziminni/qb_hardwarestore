# Product Images

**Mode:** grill · **Status:** RESOLVED 2026-10-17 · **Opened:** 2026-10-17 (as a Fog of War item)
**Phase:** 6

## The question

Does the demo render product images at all?

## What exists

The question looked like a build/no-build choice, and it is not:

- `image_url` **is** on the wire (`apps/inventory/serializers.py:82`).
- The client **already has** `flutter/lib/features/products/widgets/products_image.dart`, and six more
  files reference `imageUrl` (the product model, the form dialog, the details dialog, the archived
  dialog, the table, and the mock data).
- **Every seeded `image_url` is an empty string.**

So the UI is built and the data is blank. The only real question was whether to fill it.

## Ruling (user, 2026-10-17)

**Leave the images blank.** `products_image.dart` already renders a placeholder for an empty URL, so the
state is honest rather than broken, and **nothing is built**.

## Why not populate the seed

A real remote URL only loads with network access, so an offline or projected demo would show
**broken-image icons instead of placeholders** — strictly worse than blank. Making images reliable would
mean bundling them as assets, which is real work for a cosmetic gain. If the capstone is later graded on
visual polish, this is the decision to revisit, and the fix is bundled assets rather than URLs.

## Why not remove the UI

Deleting `products_image.dart` and the image column would throw away working UI and make the client
deliberately narrower than the API it consumes. The field stays on the wire either way.
