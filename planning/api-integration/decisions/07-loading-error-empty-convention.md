# Loading, Error and Empty State Convention

**Mode:** grill · **Status:** LOCKED 2026-10-16 · **Opened:** 2026-10-15
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

## Verified findings (source)

No convention exists for data screens, but there is exactly one working precedent to align with.

| Finding | Evidence |
| :--- | :--- |
| The only live async viewmodel uses **public mutable fields** | `auth_viewmodel.dart`: `bool isInitializing = true; bool isLoading = false; User? user; String? error;` |
| Its view renders via `Consumer` with inline null checks | `login_page.dart:265-300` — `if (error == null) return const SizedBox.shrink();`, `onPressed: viewModel.isLoading ? null : _login` |
| No data screen has loading/error/empty | The state-ish grep hits were search and filter state, not async state. |
| `ProductsViewmodel` is **synchronous** | It takes `List<Product> products` in its constructor — it has no async path at all. |
| No `core/widgets/` exists | `core/` holds only `config`, `constants`, `layout`, `network`, `theme`. |
| Two field styles already coexist | `auth_viewmodel` uses public fields; `products_viewmodel` uses private fields plus getters. |

A related wiring surprise worth its own fix: `products_page.dart` watches `InventoryViewmodel`, not
`ProductsViewmodel` — and `ProductsViewmodel` is not registered in `main.dart` at all.

## Resolution — LOCKED 2026-10-16

**Option A: viewmodels follow the `auth_viewmodel` field convention; one shared `AsyncView` widget owns the
rendering.**

```dart
// viewmodel — public fields, mirroring auth_viewmodel
bool isLoading = false;
String? error;
List<CatalogueItem> items = const [];
```

```dart
// new: flutter/lib/core/widgets/async_view.dart
AsyncView(
  isLoading: vm.isLoading,
  error: vm.error,
  isEmpty: vm.items.isEmpty,
  onRetry: vm.load,
  builder: (context) => ...,
)
```

The widget is the only new abstraction. It decides the four branches in one place, so 27 screens cannot drift
in ordering or treatment, and the only per-screen input is the empty-state copy.

Why not the alternatives:

- **Base `AsyncViewmodel` class** — would enforce `notifyListeners` and save roughly 8 lines per method, but it
  introduces inheritance the codebase uses nowhere, and two viewmodels already use private fields plus getters,
  which conflicts. Revisit only if the boilerplate proves painful across several real screens.
- **Per-screen inline** — zero new files, but 27 hand-written four-branch variants is the same dynamic that
  produced the current inconsistency. The atlas already documents how these screens drifted apart.

### Files

- New: `flutter/lib/core/widgets/async_view.dart`.
- Each wired viewmodel adopts the auth field convention **as it is touched** — no bulk migration. The work
  rides along with Phases 1-6.

### Interaction with the pagination decision

`AsyncView` is the presentation half of the problem that `getList<T>` solves on the transport side
([Pagination Envelope Strategy](./03-pagination-envelope-strategy.md)). Both exist so a screen cannot forget:
one unwraps `.results`, the other renders all four states.
