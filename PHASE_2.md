# Phase 2 — Purchasing, POS & Collectibles

**Date:** August 2026  
**Status:** ✅ Complete  
**Commits:** `cb022c8` → `88e9402` → `5edabe0`

---

## What was built

### 1. Inventory Extension (Purchasing & Stock)
**`apps/inventory/models.py`** — 6 new models:
- `Supplier` — vendor with split phone/email fields
- `PurchaseOrder` — 5-status flow (DRAFT → ORDERED → PARTIAL → COMPLETE / CANCELLED)
- `POItem` — line items with `ordered_qty`, `unit_cost`, tracked `received_qty`
- `GoodsReceipt` — delivery confirmation, links to PO
- `InventoryBatch` — FIFO batch created on receipt; `initial_qty` / `current_qty`, `unit_cost_landed`, markup, `batch_selling_price`, expiration
- `StockAdjustment` — manual corrections (4 types: SHRINKAGE/DAMAGE/CORRECTION/RETURN)
- `SystemAlert` — auto-generated alerts (LOW_STOCK/OUT_OF_STOCK/EXPIRING), resolvable

**`apps/inventory/services.py`** — Core business logic:
- `process_goods_receipt()` — converts receipt to InventoryBatch entries, updates PO status
- `allocate_fifo()` — FIFO allocator: takes a variant + qty → iterates oldest batches → deducts with `select_for_update()` lock, returns allocations
- `apply_stock_adjustment()` — applies manual corrections, fires alerts
- `_check_low_stock()` — aggregates batch qty, creates SystemAlert if below threshold

### 2. POS Module (Point of Sale)
**`apps/pos/models.py`** — 5 models:
- `Customer` — 4 customer types (WALK_IN/REGULAR/CONTRACTOR/CONSTRUCTION_FIRM), TIN, credit limit
- `SalesTransaction` — transaction_no auto-generated (TRX-YYYYMMDD-####), source (WALK_IN/REQUISITION), status (COMPLETED/VOID/REFUNDED), tax fields
- `SalesItem` — links to VariantUOM, qty/price/subtotal
- `Payment` — split payments supported (CASH/CARD/GCASH/BANK_TRANSFER), reference tracking
- `OfficialReceipt` — OneToOne to transaction, OR number auto-generated (OR-YYYYMMDD-####)

**`apps/pos/services.py`** — Checkout:
- `process_sale()` — creates transaction, items, FIFO-deducts stock, processes payments, generates OR — all in `transaction.atomic()`

### 3. Collectibles Module (Accounts Receivable)
**`apps/collectibles/models.py`** — 2 models:
- `CollectibleLedger` — tracks credit sales (OPEN/PARTIAL/PAID/OVERDUE), due_date, `is_overdue` property
- `CollectiblePayment` — logs partial/full settlements

**`apps/collectibles/views.py`** — `aging_report` action groups overdue by customer

---

## API Endpoints (Phase 2 additions)

| Method | URL | Description |
|--------|-----|-------------|
| `GET/POST` | `/api/v1/suppliers/` | Supplier CRUD |
| `GET/POST` | `/api/v1/purchase-orders/` | PO CRUD |
| `GET/POST` | `/api/v1/goods-receipts/` | Receipt CRUD |
| `POST` | `/api/v1/goods-receipts/{id}/process/` | Convert receipt to batches |
| `GET` | `/api/v1/batches/` | View FIFO batches |
| `GET/POST` | `/api/v1/adjustments/` | Stock adjustments |
| `GET` | `/api/v1/alerts/` | System alerts |
| `POST` | `/api/v1/alerts/{id}/resolve/` | Mark alert resolved |
| `GET/POST` | `/api/v1/customers/` | Customer CRUD |
| `POST` | `/api/v1/transactions/` | Process POS sale |
| `GET` | `/api/v1/transactions/daily_report/` | Daily sales totals |
| `GET` | `/api/v1/payments/` | Payment records |
| `GET` | `/api/v1/receipts/` | Official receipts |
| `GET/POST` | `/api/v1/ledgers/` | Collectible ledger |
| `POST` | `/api/v1/payments/` (collectibles) | Log receivable payment |
| `GET` | `/api/v1/ledgers/aging/` | Aging report |

---

## Next Steps (you must do this)

```bash
# 1. Rebuild Docker with new models
docker compose up -d --build

# 2. Generate + apply migrations
docker compose exec backend python manage.py makemigrations inventory pos collectibles
docker compose exec backend python manage.py migrate

# 3. Test POS flow
curl -X POST http://127.0.0.1:8000/api/v1/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'

# Save the access token, then:
# Create a supplier
# Create a PO
# Create a goods receipt
# POST /api/v1/goods-receipts/{id}/process/
# Create a transaction (POS sale)
```

## Next: Phase 3 (Requisitions)
- Construction Project, Requisition, RequisitionItem, MaterialToken
- Material release flow at POS
- Auto-post to collectibles on requisition release