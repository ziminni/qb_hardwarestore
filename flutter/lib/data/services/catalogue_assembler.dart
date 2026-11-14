import 'package:client/data/models/catalogue_item.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/stock_on_hand.dart';

/// Joins catalogue entities into rows a screen can render.
///
/// The join is unavoidable, not incidental: neither `GET /api/v1/products/` nor
/// `GET /api/v1/variants/` exposes a price or a stock quantity (verified against
/// the running API). Price lives on the selling unit and quantity on the server's
/// per-location on-hand read, so something has to bring them together — this does
/// it **once**, rather than in each of the screens that need it.
///
/// Pure and synchronous: no I/O, so it is unit-testable without a network.
///
/// [products] should come from `GET /api/v1/products/` (variants arrive nested)
/// and [stockOnHand] from `GET /api/v1/stock-on-hand/`.
///
/// Emits one [CatalogueItem] per (variant, selling unit) pair. A variant with no
/// selling unit is **excluded** — it has no chargeable price, and inventing a
/// zero price is the defect this model change exists to remove.
List<CatalogueItem> assembleCatalogue({
  required List<Product> products,
  required List<StockOnHand> stockOnHand,
}) {
  final stockByVariant = _stockByVariant(stockOnHand);
  final items = <CatalogueItem>[];

  for (final product in products) {
    for (final variant in product.variants) {
      if (variant.sellingUoms.isEmpty) continue;

      final stock = stockByVariant[variant.id] ?? 0;
      for (final uom in variant.sellingUoms) {
        items.add(
          CatalogueItem(
            product: product,
            variant: variant,
            uom: uom,
            price: uom.defaultSellingPrice,
            stockOnHand: stock,
          ),
        );
      }
    }
  }

  return List.unmodifiable(items);
}

/// Total quantity per variant, summed across its shelves (Phase 9 F1).
///
/// The rows are the SERVER's: read from `GET /api/v1/stock-on-hand/`, never
/// derived from batches here — a transfer moves stock between shelves without
/// changing this total, and the client has no business recomputing it.
Map<int, double> _stockByVariant(List<StockOnHand> rows) {
  final totals = <int, double>{};
  for (final row in rows) {
    totals.update(
      row.variantId,
      (running) => running + row.qty,
      ifAbsent: () => row.qty,
    );
  }
  return totals;
}
