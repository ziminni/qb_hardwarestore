// Phase 6 Task 6 (decision 14): the Receiving pre-fill.
//
// A delivery means "put a sticker on each thing that just arrived". The base unit
// is the one that arrived, so it gets copies = the quantity received when it is a
// countable unit; a measured base unit (m, kg) gets one; the variant's other units
// (a box of 100) were not delivered as such, so they start at 0.

import 'package:client/core/units/whole_units.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/labels/label_document.dart';

/// One label request per selling unit of a variant this delivery restocked.
///
/// [receivedQty] is in BASE units (the quantity the goods receipt recorded).
List<LabelRequest> deliveryLabelRequests({
  required String productName,
  required String variantName,
  required List<VariantUom> sellingUnits,
  required double receivedQty,
}) => [
  for (final unit in sellingUnits)
    LabelRequest(
      code: unit.barcodeQr,
      productName: productName,
      variantName: variantName,
      unitName: unit.uomCode,
      copies: _copiesFor(unit, receivedQty),
    ),
];

/// Copies for one unit: 0 when it is not what arrived, else the quantity received.
int _copiesFor(VariantUom unit, double receivedQty) {
  // A factor-1 unit IS the base unit — the thing the receipt counted.
  if (unit.conversionFactor != 1) return 0;
  if (!isWholeUnit(unit.uomCode)) return 1;
  final whole = receivedQty.floor();
  if (whole <= 0) return 0;
  return whole > labelMaxCopies ? labelMaxCopies : whole;
}
