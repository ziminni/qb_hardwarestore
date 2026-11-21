# BuildPro POS — Profit, Markup & Discount Accounting Guide

This document explains in plain language how BuildPro POS calculates **cost, markup, inline (per-item) discounts, whole-sale (cart) discounts, VAT, refunds, and operational gross profit**.

---

## 1. How Profit Is Calculated (Single Item)

Every sale line tracks two separate facts:
1. **What the customer paid** (shelf price or utang credit price, minus discounts).
2. **What the item cost the store** (the FIFO batch's landed cost `unit_cost_landed`, snapshotted onto `SalesItemDeduction.unit_cost` at the moment of sale so future restocks never rewrite past profit).

### Formula
```text
  Goods at shelf / utang price (before discounts)   [landed cost + your markup]
− Inline (per-item) discounts
− Whole-sale (cart) discounts
───────────────────────────────────────────────────
= Net merchandise sales (VAT-inclusive)
− VAT on goods (remitted to BIR, not your profit)
───────────────────────────────────────────────────
= Net merchandise sales (ex-VAT)
− Landed cost of goods sold (FIFO COGS)
───────────────────────────────────────────────────
= Operational gross profit
```

- **Gross Margin %** = `Operational Gross Profit ÷ Net Merchandise Sales (ex-VAT) × 100`
  *(How much of every peso of net sales you keep as gross profit.)*
- **Effective Markup on Cost %** = `Operational Gross Profit ÷ Landed COGS × 100`
  *(How much you earned on top of what you paid the supplier.)*

### Example (1 Bag of Cement, 12% VAT-Registered)
- **Landed Cost (FIFO COGS):** `₱180.00`
- **Shelf Price (incl. 12% VAT):** `₱280.00`
- **No discount:**
  - Customer pays: `₱280.00`
  - Net sales (ex-VAT): `₱280.00 ÷ 1.12 = ₱250.00`
  - VAT (to BIR): `₱30.00`
  - **Operational Gross Profit:** `₱250.00 − ₱180.00 = ₱70.00`
  - **Margin %:** `70 ÷ 250 = 28.0%`
  - **Markup on Cost %:** `70 ÷ 180 = 38.9%`

*(If the store is **Non-VAT**, VAT is `₱0.00`, so Net Sales = `₱280.00` and Operational Gross Profit = `₱280.00 − ₱180.00 = ₱100.00`.)*

---

## 2. Multi-Item Checkout: Inline Discount vs. Whole-Sale (Cart) Discount

When a customer buys multiple products in one checkout, discounts happen in **two strict steps**:

### Step 1 — Inline (Per-Item) Discount Applies First (That Item Only)
- A cashier gives an inline discount directly on one specific line (for example, `₱50` off a slightly scratched tool box).
- It is stored on that line as `SalesItem.item_discount_amount`.
- It **never** touches any other product in the cart.
- It is **refused** on never-discounted goods (`Product.allow_discount = False`, such as cement).

### Step 2 — Whole-Sale (Cart) Discount Applies Second (Spread Proportionally)
After inline discounts are taken off, any whole-sale (cart) discount is spread across the **eligible remaining balances** (`allow_discount = True`) and saved per line as `SalesItem.cart_discount_amount`.

#### Why do we divide each item's remaining balance by the total eligible balance, then multiply by the cart discount?
Think of it as finding **each item's percentage slice of the eligible bill**:

1. **Step A (Divide):** `Item's Remaining Balance ÷ Total Eligible Balance` = **that item's share (%) of the eligible bill**.
2. **Step B (Multiply):** `Item's Share (%) × Whole-Sale Cart Discount` = **that item's peso share of the cart discount**.

**Why proportional instead of an equal split?**
Suppose a customer buys a `₱1,000` power drill and a `₱15` pack of screws, and you give a `₱40` cart discount:
- If you split `₱40` equally (`₱20` each), the `₱15` screws would become **`−₱5`** (a negative price!) — breaking refunds and distorting profit.
- With **proportional sharing**, every eligible item gets the **exact same effective discount rate**:
  - In our example below, `₱40` off `₱400` is **10%**.
  - Tools (`₱300` remaining) is `300 ÷ 400 = 75%` of the eligible bill → absorbs `75% × ₱40 = ₱30.00` (which is **10%** of `₱300`).
  - Fasteners (`₱100` remaining) is `100 ÷ 400 = 25%` of the eligible bill → absorbs `25% × ₱40 = ₱10.00` (which is **10%** of `₱100`).
- **Exact centavo rounding:** When a split doesn't divide evenly (e.g., `₱10.00` across three equal items), BuildPro allocates integer centavos using the **largest-remainder rule** (checkout line order breaks ties), producing `₱3.34`, `₱3.33`, `₱3.33` so the parts always sum to **`₱10.00`** to the centavo.

#### Full 3-Item Worked Example
Suppose a customer checks out with:
1. **Cement** (`allow_discount = False`): `₱600.00` *(never discounted)*
2. **Tools** (`allow_discount = True`): `₱350.00` → cashier gives a **`₱50.00` inline discount** → remaining balance = **`₱300.00`**
3. **Fasteners** (`allow_discount = True`): **`₱100.00`**

Then the cashier applies a **`₱40.00` whole-sale (cart) discount**:
- **Total eligible remaining balance:** `₱300 (Tools) + ₱100 (Fasteners) = ₱400` *(Cement is excluded)*.
- **Tools slice:** `300 ÷ 400 = 75%` → `75% × ₱40 = ₱30.00`
- **Fasteners slice:** `100 ÷ 400 = 25%` → `25% × ₱40 = ₱10.00`
- **Cement slice:** `₱0.00`

| Item | Shelf Price | Inline Discount | Remaining Eligible | Slice of Eligible Bill | Cart Discount Share | Final Net (incl. VAT) |
|---|---:|---:|---:|---:|---:|---:|
| Cement *(excluded)* | ₱600.00 | ₱0.00 | — | 0% | ₱0.00 | **₱600.00** |
| Tools | ₱350.00 | −₱50.00 | ₱300.00 | 75% (`300 ÷ 400`) | −₱30.00 | **₱270.00** |
| Fasteners | ₱100.00 | ₱0.00 | ₱100.00 | 25% (`100 ÷ 400`) | −₱10.00 | **₱90.00** |
| **Total** | **₱1,050.00** | **−₱50.00** | **₱400.00** | **100%** | **−₱40.00** | **₱960.00** |

---

## 3. Why Storing Exact Shares Per Line Matters

1. **Accurate Partial Refunds:** If the customer returns only the **Fasteners**, BuildPro refunds **`₱90.00`** (what they actually paid after their `₱10` share of the cart discount), not the `₱100.00` shelf price.
2. **Honest Category Analytics:** Reports charge the `₱80` discount to **Tools**, `₱10` to **Fasteners**, and `₱0` to **Cement**, so category sales and profit stay accurate.
3. **Combined Cashier Approval & Shift Limits:** Manager approval (`discount_cap_percent`) and shift cumulative limits (`shift_discount_cap_percent`) always measure the **combined** discount (`inline + cart`), so splitting a discount cannot bypass approval rules.

---

## 4. What Is Kept Outside Merchandise Profit

To keep your product margins honest (following standard retail/IAS 2 reporting practice):
- **VAT collected** belongs to BIR, not profit.
- **Delivery fees** (service/pass-through charge) are shown separately outside merchandise profit.
- **Payment fees** (GCash / Card / Bank transfer surcharges) are shown separately outside merchandise profit.
- **Legacy sales before cost snapshots (migration `pos.0022`):** Older stock deductions have `unit_cost = NULL`. Reports explicitly flag them as **Partial cost history** instead of pretending their cost was `₱0.00`.
