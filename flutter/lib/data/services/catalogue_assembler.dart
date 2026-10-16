import 'package:client/data/models/catalogue_item.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';

/// Joins catalogue entities into rows a screen can render.
///
/// The join is unavoidable, not incidental: neither `GET /api/v1/products/` nor
/// `GET /api/v1/variants/` exposes a price or a stock quantity (verified against
/// the running API). Price lives on the selling unit and stock lives on the FIFO
/// batches, so something has to bring them together — this does it **once**,
/// rather than in each of the screens that need it.
///
/// Pure and synchronous: no I/O, so it is unit-testable without a network.
///
/// [products] should come from `GET /api/v1/products/` (variants arrive nested)
/// and [batches] from `GET /api/v1/batches/`.
///
/// Emits one [CatalogueItem] per (variant, selling unit) pair. A variant with no
/// selling unit is **excluded** — it has no chargeable price, and inventing a
/// zero price is the defect this model change exists to remove.
List<CatalogueItem> assembleCatalogue({
  required List<Product> products,
  required List<InventoryBatch> batches,
}) {
  final stockByVariant = _stockByVariant(batches);
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

/// Total remaining quantity per variant, summed across its batches.
Map<int, double> _stockByVariant(List<InventoryBatch> batches) {
  final totals = <int, double>{};
  for (final batch in batches) {
    totals.update(
      batch.variantId,
      (running) => running + batch.currentQty,
      ifAbsent: () => batch.currentQty,
    );
  }
  return totals;
}
