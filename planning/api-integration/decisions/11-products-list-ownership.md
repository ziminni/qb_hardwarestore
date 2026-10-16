# Product List Ownership in the Products Screen

**Mode:** grill · **Status:** LOCKED 2026-10-16 · **Phase:** 0 (the last open row)
Resolves the Cleanup row of the Phase 0 hand-off table, and corrects the premise of the Registration row
beside it.

## The question

`products_page.dart` treats **two different product lists** as authoritative and applies every mutation to
both. Which one owns the data, and where do the screen's stock counts come from?

## What was verified first

`products_page.dart`:

```dart
// :179 — a SNAPSHOT copy, taken once at provider creation
ProductsViewmodel(context.read<InventoryViewmodel>().products)

// :48-53 — every mutation applied TWICE, to two independent lists
viewModel.addProduct(result.product);
inventory.addProduct(result.product, openingStock: result.openingStock);
viewModel.updateProduct(result.product);
inventory.updateProduct(result.product);
```

Plus `archiveProduct`/`archiveSelectedProducts` at :127-128 and :164-167, which do the same thing.

| Fact | Evidence |
| :--- | :--- |
| `InventoryViewmodel` is the real store | 6 consumers of `stockRecords` (pos, reports, 3 inventory pages, products_page) |
| `ProductsViewmodel` has **one** consumer | `products_page.dart` only; nothing else constructs it |
| `ProductsViewmodel` holds a **copy** | its constructor takes `List<Product> products` and does `List<Product>.of(products)` |
| Every mutation is applied twice | the call sites above; each viewmodel computes its own `max(id)+1`, so the two can disagree |

**Both lists are the same list.** This is not a layering choice that was made — it is a duplication that
happened, and it is the source of the "two id authorities" the code review flagged: any mutation the page
forgets to mirror leaves the table and the counters disagreeing.

### Correction to the Registration row

That row reads *"Register `ProductsViewmodel` and `PosTransactionViewmodel` in `main.dart` — only 6 of 8
viewmodels are currently wired."* **Its premise is wrong.** Both viewmodels *are* provided — screen-scoped,
at `products_page.dart:179` and `pos_transaction_page.dart:35`. The row inferred "unwired" from `main.dart`
not listing them, which is not the same thing.

And the two are not the same case:

| Viewmodel | What the provider passes in | Verdict |
| :--- | :--- | :--- |
| `PosTransactionViewmodel` | the **live** `InventoryViewmodel` and `ProductTrackingViewmodel`, and it registers listeners on both (`pos_transaction_viewmodel.dart:9-10`) | **already correct** — no change |
| `ProductsViewmodel` | a **snapshot** `List<Product>` | **the defect** — drifts the moment anything mutates stock or catalogue |

So the pattern this decision needs already exists one screen over. `ProductsViewmodel` should copy it.

## Options considered

| Option | Trade-off |
| :--- | :--- |
| **ProductsViewmodel holds view state only** | One authority; duplicate deleted; smallest change. |
| `ProductsViewmodel` becomes the single store | Tidier long-term separation, but re-points 6 `stockRecords` consumers and re-opens the 16-reader surface just migrated. |
| Register globally and keep both lists in sync | Cheapest now; the duplicated list and the double mutation both survive. |

## Resolution — LOCKED 2026-10-16

**`ProductsViewmodel` becomes view state only.** It owns search, category and brand filters, sorting, paging
and selection — and **no product data**. It reads the list live from `InventoryViewmodel` and listens for
changes, exactly as `PosTransactionViewmodel` already does.

Consequences this locks:

- `ProductsViewmodel._products` and its `List<Product>` constructor parameter are **deleted**.
- Its constructor takes the `InventoryViewmodel` and calls `addListener` in the way
  `PosTransactionViewmodel` does; it must also `removeListener` in `dispose`.
- `products`, `totalProducts`, `archivedProducts`, `totalVariants`, `categories`, `brands`,
  `filteredProducts`, `visibleProducts` become **derived** getters over the injected store rather than over a
  private copy.
- `addProduct`, `updateProduct`, `archiveProduct` and `archiveSelectedProducts` **delegate** to
  `InventoryViewmodel` — they stop being a second write path. `products_page.dart` then makes each call
  **once**.
- **`ProductsViewmodel` is NOT registered in `main.dart`.** It is screen-scoped view state, and registering it
  globally would share one search box, one page number and one selection across every navigation. The
  Registration row's instruction to register it is superseded by this decision. `PosTransactionViewmodel` is
  likewise left screen-scoped, for the same reason: a half-finished cart should not survive leaving the till.
- No change to `InventoryViewmodel`'s public surface, and no change to the 16 migrated readers.

*Cost if wrong:* the products screen's filters now rebuild whenever stock changes (a listener on the store),
which is a rebuild cost the current snapshot avoids; and `ProductsViewmodel` can no longer be constructed or
unit-tested without an `InventoryViewmodel`. Both are acceptable — the first is what keeps the table and the
counters honest, and the second is already true in practice since the page always had one to hand.

## What this leaves open

Nothing that gates Phase 0. Phase 1 will decide *what fetches the API* — under this decision the answer is
whatever ends up owning the list (`InventoryViewmodel`, or a catalogue viewmodel that replaces it), because
the screen's view state deliberately owns no data.
