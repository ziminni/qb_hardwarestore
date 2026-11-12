# Cleanup list (deferred Minors and known gaps)

**Status:** Locked 2026-11-12 (by: me — owner chose "Fix all"; list verified by research against current source)
**Phase:** 6

Each item was confirmed to still exist on 2026-11-12 (read-only sweep, file:line evidence in the session record). Fix size S = small, M = medium.

| # | Item | Where | Size | Risk |
|---|---|---|---|---|
| 16 | Sales orders/quotations: `status` writable, no transition rules or audit; DELETE of an order with a delivery → 500 | `apps/pos/views.py:979-1007`, `serializers.py:344-353, 415-421` | M | High |
| 6 | Supplier-bill discount allocation not capped at the PO header discount on over-receipt | `apps/inventory/payables.py:106-119` | S | Medium (money) |
| 14 | Archived product's selling unit accepted on quotation/order lines | `apps/pos/serializers.py:318-337, 377-396` | S | Medium |
| 19 | Quotation/order/delivery numbers race (read-max-then-add, no lock) → 500 | `common/numbering.py:12-23` | S/M | Medium |
| 9 | `vatRate!` crash on PO details when a total exists without a rate | `flutter/.../purchases_details_dialog.dart:127-131` | S | Low |
| 18 | Till stock badge uses hardcoded threshold 10, not the product's threshold | `flutter/.../pos_product_browser.dart:400` | S | Low |
| 1 | Broad `except Exception` turns real errors into 400 | `apps/users/views.py:332` | S | Low |
| 2 | Requisitions import private `_money_round` | `apps/requisitions/services.py:447` | S | Low |
| 3 | No-change store-settings PATCH still saves and audits | `apps/pos/views.py` settings `patch()` | S | Low |
| 4 | No test feeds a nonzero server `change_given` into the receipt | Flutter receipt tests | S | Low |
| 7 | Wrong arithmetic example in payables docstring | `apps/inventory/payables.py:100` | S | None |
| 8 | PO serializer docstrings misstate unit error/null behaviour | `apps/inventory/serializers.py:623-633` | S | Low |
| 10 | Delivery money validator duplicated in two dialogs | `sales_order_form_dialog.dart:565-573`, `pos_payment_dialog.dart:664-674` | S | Low |
| 11 | "New sales order" shown when the page failed to load | `sales_orders_page.dart:105-112` | S | Low |
| 12 | Legacy product with no location id cannot have its location changed | `products_form_dialog.dart:208-211` | S | Low |
| 13 | Double-tap "add location" shows a false "added" message | `storage_locations_viewmodel.dart:95` | S | Low |
| 15 | Order price/fee and till fee fields can clip their error text | `sales_order_form_dialog.dart:437-444, 528-535`, `pos_payment_dialog.dart:655-660` | S | Low |
| 17 | Seed: variants keyed by bare name ("Standard" collides); packaging guard cannot repair half-built data | `seed_demo.py:112-146, 214-218, 660` | M | Low (demo data) |

## Not fixed (delegated)

- **#5 legacy VOID change backfill** in applied migration 0014: cosmetic, already applied everywhere; rewriting an applied migration is riskier than the blemish.
- **#20 expiry alerts (EXPIRING never raised):** a new feature, not a fix — listed in the MAP Fog of War for the owner to schedule.

## Overlap

Item 16 is partly superseded by Phase 7 (orders get real lifecycle actions). Phase 6 makes order/quotation `status` read-only, removes DELETE (orders) / guards it (quotations), and audits writes; Phase 7 then adds the order actions.
