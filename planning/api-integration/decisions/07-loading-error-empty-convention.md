# Loading, Error and Empty State Convention

**Mode:** grill · **Status:** OPEN · **Opened:** 2026-10-15
**Phase:** 0 — graduated from Fog of War when the slice order locked.

## The question

Where does the loading / error / empty state convention live, so that every wired screen gets all three
without each one inventing its own?

## Why it matters

Every list in the client is currently **synchronous**, so no screen has any of these states. The moment a
screen talks to the network it can be loading, can fail, and can legitimately have zero rows — and the atlas
counts 27 such screens. Deciding this once in Phase 0 is far cheaper than retrofitting 27 screens later.

It is also the difference between a demo that looks finished and one that shows a blank page for two seconds
and then appears broken.

## Options

| Option | Trade-off |
| :--- | :--- |
| **Shared state enum + a `<AsyncView>` wrapper widget** | One place to change; every screen gets identical behaviour. Adds an abstraction the codebase does not have yet. |
| **Base viewmodel class exposing `isLoading` / `error` / `isEmpty`** | Fits the existing MVVM shape closely; still needs a widget side for consistent rendering. |
| **Per-screen handling** | No new abstraction, fastest for screen one; guarantees 27 inconsistent implementations. |

## Recommendation

A shared widget wrapper backed by a small state enum, because the client already has shared layout widgets
(`core/layout/`) to sit beside, and 27 screens is far too many to keep consistent by hand. Confirm against
`core/layout/inventory_skeleton_layout.dart` so the new wrapper fits the existing conventions rather than
competing with them.

## Resolution

_Unresolved — Phase 0, and it blocks every later screen._
