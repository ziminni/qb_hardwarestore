import 'package:client/data/models/json_field.dart';

/// One batch pair a transfer line moved: the lot it left, the NEW lot it landed
/// on, and how much (Phase 9 F3, plan Design 2/6).
///
/// A line drawn from two deliveries writes two moves whose sum is the line's
/// `baseQty`, so the slip can say where the stock came from without a request
/// per lot. Only the ids cross the wire — the slip names the SHELVES, not the
/// batches.
class StockTransferMove {
  const StockTransferMove({
    required this.id,
    required this.sourceBatchId,
    required this.destBatchId,
    required this.qty,
  });

  final int id;
  final int sourceBatchId;
  final int destBatchId;
  final double qty;

  factory StockTransferMove.fromJson(Map<String, dynamic> json) =>
      StockTransferMove(
        id: intField(json, 'id'),
        sourceBatchId: intField(json, 'source_batch'),
        destBatchId: intField(json, 'dest_batch'),
        qty: decimalField(json, 'qty'),
      );
}

/// One line of the numbered slip: what the clerk typed, and the stock that
/// actually moved.
///
/// Both figures are kept because stock is counted in BASE units while the clerk
/// and the slip speak packages: `2 BAG` moved `24 PC` of stock.
class StockTransferLine {
  const StockTransferLine({
    required this.id,
    required this.variantUomId,
    required this.variantId,
    required this.variantName,
    required this.productName,
    required this.unit,
    required this.qty,
    required this.baseQty,
    required this.moves,
  });

  final int id;
  final int variantUomId;
  final int variantId;
  final String variantName;
  final String productName;

  /// The selling unit's code (`BAG`), as the clerk counted.
  final String unit;

  /// The quantity as entered, in [unit].
  final double qty;

  /// The stock that moved, in the variant's base unit.
  final double baseQty;

  final List<StockTransferMove> moves;

  /// `Portland cement · 40kg` — the product, then the variant. A body that
  /// carries no product name falls back to the variant rather than printing a
  /// dangling separator.
  String get label => productName.isEmpty
      ? variantName
      : '$productName · $variantName';

  factory StockTransferLine.fromJson(Map<String, dynamic> json) =>
      StockTransferLine(
        id: intField(json, 'id'),
        variantUomId: intField(json, 'variant_uom'),
        variantId: intField(json, 'variant'),
        variantName: stringField(json, 'variant_name'),
        productName: stringField(json, 'product_name'),
        unit: stringField(json, 'unit'),
        qty: decimalField(json, 'qty'),
        baseQty: decimalField(json, 'base_qty'),
        moves: nestedList(json, 'moves', StockTransferMove.fromJson),
      );
}

/// A recorded move of stock between two shelves — mirrors `GET/POST
/// /api/v1/stock-transfers/` (Phase 9 B4 wire, F3 screens).
///
/// **Append-only.** The route answers 405 to PUT/PATCH/DELETE for every role, so
/// this model has no writer and no `copyWith`: a mistake is corrected by a
/// transfer in the other direction, never by editing the slip.
///
/// The stock moved AT ONCE — there is no in-transit state and nothing to
/// receive. The slip, the batches and the audit row are the whole record.
class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.number,
    required this.fromLocationId,
    required this.fromLocationName,
    required this.toLocationId,
    required this.toLocationName,
    required this.userId,
    required this.userName,
    required this.remarks,
    required this.createdAt,
    required this.lines,
  });

  final int id;

  /// `TR-YYYYMMDD-NNNN`, reserved by the server for THIS act.
  final String number;

  final int fromLocationId;
  final String fromLocationName;
  final int toLocationId;
  final String toLocationName;
  final int userId;
  final String userName;
  final String remarks;
  final DateTime? createdAt;
  final List<StockTransferLine> lines;

  int get lineCount => lines.length;

  /// Everything the slip moved, in base units.
  double get movedBaseQty => lines.fold(0, (sum, line) => sum + line.baseQty);

  /// `Store → Bodega`.
  String get routeLabel => '$fromLocationName → $toLocationName';

  factory StockTransfer.fromJson(Map<String, dynamic> json) => StockTransfer(
    id: intField(json, 'id'),
    number: stringField(json, 'number'),
    fromLocationId: intField(json, 'from_location'),
    fromLocationName: stringField(json, 'from_location_name'),
    toLocationId: intField(json, 'to_location'),
    toLocationName: stringField(json, 'to_location_name'),
    userId: intField(json, 'user'),
    userName: stringField(json, 'user_name'),
    remarks: stringField(json, 'remarks'),
    createdAt: nullableDateField(json, 'created_at'),
    lines: nestedList(json, 'lines', StockTransferLine.fromJson),
  );
}

/// One quantity as the dialog collected it: the SELLING UNIT the clerk counted in
/// and the amount.
///
/// A record rather than a class because it crosses the widget/viewmodel line in
/// both directions and both sides can name the same shape without one importing
/// the other.
typedef StockTransferQty = ({int variantUomId, double qty});

/// A transfer as the dialog collected it, before it becomes the wire body.
class StockTransferRequest {
  const StockTransferRequest({
    required this.fromLocationId,
    required this.toLocationId,
    required this.lines,
    this.remarks = '',
  });

  final int fromLocationId;
  final int toLocationId;
  final String remarks;
  final List<StockTransferQty> lines;

  /// `{from_location, to_location, remarks, lines:[{variant_uom, qty}]}` — the
  /// body `StockTransferCreateSerializer` validates. The quantity is the
  /// SELLING unit's; the server converts it to base and refuses a fraction it
  /// cannot store, so no conversion happens here.
  Map<String, dynamic> toJson() => {
    'from_location': fromLocationId,
    'to_location': toLocationId,
    'remarks': remarks.trim(),
    'lines': [
      for (final line in lines)
        {'variant_uom': line.variantUomId, 'qty': line.qty},
    ],
  };
}
