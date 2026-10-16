import 'package:client/data/models/variant_uom.dart';

/// Rebuilds a variant's selling units after the product form has edited the
/// **primary** (base) selling unit.
///
/// The form edits one unit — the base one — so this replaces that unit in place
/// and **preserves every other unit**. Rebuilding the list from form input alone
/// would silently delete additional units: harmless while the mock carries one
/// unit per variant, but real API data can carry several (the API models
/// `selling_uoms` as a list), and then one edit would destroy them.
///
/// The primary unit keeps its `id` so the row identity survives an edit, and
/// inherits the existing conversion factor rather than resetting it to 1.
///
/// Decision 08 is why the price comes from here at all: the charged price is the
/// selling unit's `default_selling_price`, never a batch price.
List<VariantUom> mergePrimarySellingUom({
  required List<VariantUom> existing,
  required int variantId,
  required String uomCode,
  required String barcodeQr,
  required double defaultSellingPrice,
}) {
  final current = existing.isEmpty ? null : existing.first;
  final primary = VariantUom(
    id: current?.id ?? 0,
    variantId: variantId,
    uomId: current?.uomId ?? 0,
    uomCode: uomCode,
    uomName: current?.uomName ?? uomCode,
    barcodeQr: barcodeQr,
    conversionFactor: current?.conversionFactor ?? 1,
    defaultSellingPrice: defaultSellingPrice,
  );
  return <VariantUom>[primary, ...existing.skip(1)];
}
