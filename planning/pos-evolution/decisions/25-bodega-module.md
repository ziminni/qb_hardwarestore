# Bodega module and the Bodega Checker

**Status:** Locked 2026-11-17, **revised 2026-11-18** (by: me — owner: the checker only reads and validates; the stocker does every movement in and out)
**Phase:** Bodega module (after 9)

## Context

Owner (2026-11-17): the Bodega is not backup storage for the Store but secondary storage with its own inventory: gravel, sand, hollow blocks and other bulk goods live there. A person in charge, the **checker**, works there and should see only the Bodega.

Phase 9 already gave every batch a shelf (`InventoryBatch.location`), so Bodega stock is counted. Every sale records which batch each unit came from (`SalesItemDeduction`), and linked returns write negative rows against the same batches. Nothing recorded the hand-over at the Bodega gate, and nobody owned the Bodega's counts.

## Decisions

1. **Bodega shelves.** `StorageLocation.is_bodega` marks a checker-run shelf; migration `inventory.0019` marks the existing "Bodega". A product whose home (`stored_at`) is a Bodega shelf is a Bodega item. (by: me)
2. **Bodega Checker role.** New group `Bodega Checker`, role code `bodega`, its own client area (`/bodega/…`): Bodega stock, Release goods, Release log, Counts & damage. The role sits in no other permission list, so it cannot ring sales, read money or edit the catalogue. (by: me)
3. **Claim → release.** A paid sale that took goods from a Bodega shelf is a **claim**. The checker finds it by transaction or OR number, sees paid / released / left, and records a numbered release (`BR-YYYYMMDD-NNNN`: who received it, truck plate, notes). **Partial releases** are allowed, and more than is left is refused (`RELEASE_EXCEEDS_CLAIM`). (by: me)
4. **Deliveries are checked before they are stock (rev. 2026-11-18).** The stocker records every delivery in Receiving. A line bound for a Bodega shelf does not become stock: it waits as a `BodegaDelivery` (`BD-YYYYMMDD-NNNN`, *for checking*). The checker enters, per line, how much arrived **good** and how much is **damaged**. On confirm, the delivered quantity is stocked on the Bodega shelf, and at once **damaged pieces are written off** (`DAMAGE` adjustment) and **missing pieces too** (`SHRINKAGE`). The books end at the good quantity. The bill and the PO follow the stocker's receipt, untouched by the check. (by: me — "always write off")
5. **Receipt QR (rev. 2026-11-18).** Every printed receipt carries a QR code of its OR number. The checker scans it with the phone camera to open the pick-up. Desktop types the OR number or uses a USB scanner. (by: me)
6. **Phone-first Android app for the checker (rev. 2026-11-18).** Pick-ups (landing page, *Scan receipt QR*), Deliveries to check, Bodega stock (read only), History. (by: me)
7. **No checker counts (rev. 2026-11-18).** The first version's count and manager-approval flow is removed: counting stays with the stocker. (by: me)

## Delegated defaults (owner may override)

- **Stock leaves the books at the sale, as today.** The release does not move stock. The Bodega screens show *Can still sell* (books), *Waiting pick-up* (paid, not collected) and *Should be on site* (books + waiting). This avoids reworking `process_sale`, returns, CPMS release and reports. Revisit if the owner wants stock to leave only at release.
- **Claims are derived, not stored:** sold-from-Bodega (deductions) minus linked returns minus releases. Nothing is written at sale time, so CPMS releases and fulfilled sales orders that draw from the Bodega become claims too.
- **Claims never expire.**
- **Who may release or confirm deliveries:** Bodega Checker, Stock Manager, Store Manager and Admin (`IsBodegaRole`), so a day without the checker does not stop pick-ups or deliveries.
- **Write-offs are recorded under the checker** who confirmed, with the `BD-…` number in the remarks, so they appear in the stocker's Stock adjustments.
- **Audit:** releases log as `RELEASE`, delivery checks as `RECEIPT`.

## Not done here (owner to decide)

- **"Not a backup" in the allocator.** Decision 21 still lets a sale take a Store-home product from the Bodega shelf when the Store runs out (home first, then other shelves). Making Bodega stock unreachable for Store-home products (and the reverse) changes decision 21 §2 and is left for an explicit owner ruling.
- **Store delivery trucks:** delivery slips do not yet require a Bodega release first.

## Consequences

- New backend app `apps.bodega` (models `BodegaRelease`, `BodegaReleaseLine`, `BodegaDelivery`, `BodegaDeliveryLine`), mounted at `/api/v1/bodega/`. `process_goods_receipt` holds Bodega lines for the check.
- The project's migration tests unapply `bodega` while they roll inventory or pos back, because `bodega` depends on their latest migrations.
- New client area `bodega` (five areas now); the merged sidebar heading order is Till, Sales, Stock, Bodega, Admin.
- Seed adds `checker` / `demo1234` on a fresh database only.
