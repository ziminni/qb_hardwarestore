import 'package:client/data/models/json_field.dart';

/// Bodega module wire shapes (decision 25; ENDPOINTS.md §3.8).
///
/// Every quantity is in the product's BASE unit ([unit]), the unit stock is
/// kept in — cu.m for gravel, PC for hollow blocks.

/// One product on one Bodega shelf: the books, what is paid for but not yet
/// collected, and what should physically be on the ground.
class BodegaStockRow {
  const BodegaStockRow({
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.category,
    required this.unit,
    required this.locationId,
    required this.locationName,
    required this.isHome,
    required this.onHand,
    required this.unreleased,
    required this.physical,
    required this.minStock,
    this.forChecking = 0,
    this.awaitingDispatch = 0,
  });

  final int variantId;
  final String productName;
  final String variantName;
  final String category;
  final String unit;
  final int locationId;
  final String locationName;
  final bool isHome;

  /// The books: what the till may still sell.
  final double onHand;

  /// Paid for and still waiting at the Bodega.
  final double unreleased;

  /// Sold for delivery but not yet sent out.
  final double awaitingDispatch;

  /// [onHand] + [unreleased] + [awaitingDispatch]: what a count should find.
  final double physical;
  final double minStock;

  /// Delivered to the Bodega, not yet confirmed by the checker (not stock yet).
  final double forChecking;

  String get label => '$productName — $variantName';
  bool get isLow => minStock > 0 && onHand <= minStock;

  factory BodegaStockRow.fromJson(Map<String, dynamic> json) => BodegaStockRow(
    variantId: intField(json, 'variant_id'),
    productName: stringField(json, 'product_name'),
    variantName: stringField(json, 'variant_name'),
    category: stringField(json, 'category'),
    unit: stringField(json, 'unit'),
    locationId: intField(json, 'location_id'),
    locationName: stringField(json, 'location_name'),
    isHome: boolFieldOr(json, 'is_home', or: false),
    onHand: decimalField(json, 'on_hand'),
    unreleased: decimalField(json, 'unreleased'),
    awaitingDispatch: json['awaiting_dispatch'] == null
        ? 0
        : decimalField(json, 'awaiting_dispatch'),
    physical: decimalField(json, 'physical'),
    minStock: decimalField(json, 'min_stock'),
    forChecking: json['for_checking'] == null
        ? 0
        : decimalField(json, 'for_checking'),
  );
}

/// One product a receipt may still collect from one Bodega shelf.
class BodegaClaimLine {
  const BodegaClaimLine({
    required this.variantId,
    required this.label,
    required this.unit,
    required this.locationId,
    required this.locationName,
    required this.sold,
    required this.released,
    required this.remaining,
  });

  final int variantId;
  final String label;
  final String unit;
  final int locationId;
  final String locationName;
  final double sold;
  final double released;
  final double remaining;

  factory BodegaClaimLine.fromJson(Map<String, dynamic> json) =>
      BodegaClaimLine(
        variantId: intField(json, 'variant'),
        label: stringField(json, 'label'),
        unit: stringField(json, 'unit'),
        locationId: intField(json, 'location'),
        locationName: stringField(json, 'location_name'),
        sold: decimalField(json, 'sold'),
        released: decimalField(json, 'released'),
        remaining: decimalField(json, 'remaining'),
      );

  Map<String, dynamic> toJson() => {
    'variant': variantId,
    'label': label,
    'unit': unit,
    'location': locationId,
    'location_name': locationName,
    'sold': sold.toStringAsFixed(2),
    'released': released.toStringAsFixed(2),
    'remaining': remaining.toStringAsFixed(2),
  };
}

/// A sale's Bodega claim: what was paid for, handed over and still to collect.
class BodegaClaim {
  const BodegaClaim({
    required this.saleId,
    required this.transactionNo,
    required this.orNumber,
    required this.customerName,
    required this.soldAt,
    required this.isOpen,
    required this.remainingTotal,
    required this.lines,
    this.releases = const [],
    this.smsCode = '',
  });

  final int saleId;
  final String transactionNo;
  final String orNumber;
  final String customerName;
  final DateTime? soldAt;
  final bool isOpen;
  final double remainingTotal;
  final List<BodegaClaimLine> lines;

  /// Only the single-receipt lookup carries the hand-over history.
  final List<BodegaRelease> releases;

  /// Optional 4-digit SMS verification code for offline Bodega release replies.
  final String smsCode;

  factory BodegaClaim.fromJson(Map<String, dynamic> json) => BodegaClaim(
    saleId: intField(json, 'sale'),
    transactionNo: stringField(json, 'transaction_no'),
    orNumber: json['or_number'] as String? ?? '',
    customerName: json['customer_name'] as String? ?? '',
    soldAt: nullableDateField(json, 'sold_at'),
    isOpen: boolFieldOr(json, 'is_open', or: false),
    remainingTotal: decimalField(json, 'remaining_total'),
    lines: nestedList(json, 'lines', BodegaClaimLine.fromJson),
    releases: nestedList(json, 'releases', BodegaRelease.fromJson),
    smsCode: json['sms_code'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'sale': saleId,
    'transaction_no': transactionNo,
    'or_number': orNumber,
    'customer_name': customerName,
    'sold_at': soldAt?.toIso8601String(),
    'is_open': isOpen,
    'remaining_total': remainingTotal.toStringAsFixed(2),
    'lines': [for (final line in lines) line.toJson()],
    'releases': [for (final release in releases) release.toJson()],
    'sms_code': smsCode,
  };
}

class BodegaReleaseLine {
  const BodegaReleaseLine({
    required this.variantId,
    required this.label,
    required this.unit,
    required this.locationName,
    required this.qty,
  });

  final int variantId;
  final String label;
  final String unit;
  final String locationName;
  final double qty;

  factory BodegaReleaseLine.fromJson(Map<String, dynamic> json) =>
      BodegaReleaseLine(
        variantId: intField(json, 'variant'),
        label: stringField(json, 'label'),
        unit: stringField(json, 'unit'),
        locationName: stringField(json, 'location_name'),
        qty: decimalField(json, 'qty'),
      );

  Map<String, dynamic> toJson() => {
    'variant': variantId,
    'label': label,
    'unit': unit,
    'location_name': locationName,
    'qty': qty.toStringAsFixed(2),
  };
}

/// One hand-over at the Bodega (`BR-YYYYMMDD-NNNN`).
class BodegaRelease {
  const BodegaRelease({
    required this.id,
    required this.number,
    required this.transactionNo,
    required this.customerName,
    required this.checkerName,
    required this.receivedBy,
    required this.plateNo,
    required this.notes,
    required this.createdAt,
    required this.lines,
  });

  final int id;
  final String number;
  final String transactionNo;
  final String customerName;
  final String checkerName;
  final String receivedBy;
  final String plateNo;
  final String notes;
  final DateTime? createdAt;
  final List<BodegaReleaseLine> lines;

  String get summary => [
    for (final line in lines) '${_qty(line.qty)} ${line.unit} ${line.label}',
  ].join(', ');

  factory BodegaRelease.fromJson(Map<String, dynamic> json) => BodegaRelease(
    id: intField(json, 'id'),
    number: stringField(json, 'number'),
    transactionNo: stringField(json, 'transaction_no'),
    customerName: json['customer_name'] as String? ?? '',
    checkerName: json['checker_name'] as String? ?? '',
    receivedBy: stringField(json, 'received_by'),
    plateNo: json['plate_no'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    createdAt: nullableDateField(json, 'created_at'),
    lines: nestedList(json, 'lines', BodegaReleaseLine.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'transaction_no': transactionNo,
    'customer_name': customerName,
    'checker_name': checkerName,
    'received_by': receivedBy,
    'plate_no': plateNo,
    'notes': notes,
    'created_at': createdAt?.toIso8601String(),
    'lines': [for (final line in lines) line.toJson()],
  };
}

String _qty(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

/// One product on a supplier delivery to the Bodega, as the checker confirms it.
class BodegaDeliveryLine {
  const BodegaDeliveryLine({
    required this.id,
    required this.variantId,
    required this.label,
    required this.unit,
    required this.isWhole,
    required this.deliveredQty,
    this.goodQty,
    this.damagedQty,
    this.missingQty,
    this.remarks = '',
    this.photoUrl = '',
  });

  final int id;
  final int variantId;
  final String label;
  final String unit;

  /// Counted in whole pieces (hollow blocks) rather than fractions (cu.m).
  final bool isWhole;

  /// What the stocker recorded as received.
  final double deliveredQty;
  final double? goodQty;
  final double? damagedQty;
  final double? missingQty;
  final String remarks;

  /// The checker's photo of the item as it arrived; empty until one is taken.
  final String photoUrl;

  factory BodegaDeliveryLine.fromJson(Map<String, dynamic> json) =>
      BodegaDeliveryLine(
        id: intField(json, 'id'),
        variantId: intField(json, 'variant'),
        label: stringField(json, 'label'),
        unit: stringField(json, 'unit'),
        isWhole: boolFieldOr(json, 'is_whole', or: false),
        deliveredQty: decimalField(json, 'delivered_qty'),
        goodQty: json['good_qty'] == null
            ? null
            : decimalField(json, 'good_qty'),
        damagedQty: json['damaged_qty'] == null
            ? null
            : decimalField(json, 'damaged_qty'),
        missingQty: json['missing_qty'] == null
            ? null
            : decimalField(json, 'missing_qty'),
        remarks: json['remarks'] as String? ?? '',
        photoUrl: json['photo_url'] as String? ?? '',
      );
}

/// A supplier delivery to the Bodega (`BD-YYYYMMDD-NNNN`). Not stock until the
/// checker confirms it.
class BodegaDelivery {
  const BodegaDelivery({
    required this.id,
    required this.number,
    required this.locationName,
    required this.supplierName,
    required this.receivedByName,
    required this.status,
    required this.checkedByName,
    required this.checkedAt,
    required this.notes,
    required this.createdAt,
    required this.lines,
  });

  final int id;
  final String number;
  final String locationName;
  final String supplierName;
  final String receivedByName;

  /// `PENDING` (for checking) or `CHECKED`.
  final String status;
  final String checkedByName;
  final DateTime? checkedAt;
  final String notes;
  final DateTime? createdAt;
  final List<BodegaDeliveryLine> lines;

  bool get isPending => status == 'PENDING';
  double get damagedTotal =>
      lines.fold(0, (sum, line) => sum + (line.damagedQty ?? 0));

  factory BodegaDelivery.fromJson(Map<String, dynamic> json) => BodegaDelivery(
    id: intField(json, 'id'),
    number: stringField(json, 'number'),
    locationName: stringField(json, 'location_name'),
    supplierName: json['supplier_name'] as String? ?? '',
    receivedByName: json['received_by_name'] as String? ?? '',
    status: stringField(json, 'status'),
    checkedByName: json['checked_by_name'] as String? ?? '',
    checkedAt: nullableDateField(json, 'checked_at'),
    notes: json['notes'] as String? ?? '',
    createdAt: nullableDateField(json, 'created_at'),
    lines: nestedList(json, 'lines', BodegaDeliveryLine.fromJson),
  );
}

/// What the checker hands over: `[(variant, shelf, qty)]` against one receipt.
class BodegaReleaseRequest {
  const BodegaReleaseRequest({
    required this.receipt,
    required this.receivedBy,
    required this.lines,
    this.plateNo = '',
    this.notes = '',
    this.idempotencyKey = '',
  });

  final String receipt;
  final String receivedBy;
  final String plateNo;
  final String notes;
  final String idempotencyKey;
  final List<({int variantId, int locationId, double qty})> lines;

  BodegaReleaseRequest withIdempotencyKey(String key) => BodegaReleaseRequest(
    receipt: receipt,
    receivedBy: receivedBy,
    plateNo: plateNo,
    notes: notes,
    idempotencyKey: key,
    lines: lines,
  );

  factory BodegaReleaseRequest.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    return BodegaReleaseRequest(
      receipt: stringField(json, 'receipt'),
      receivedBy: stringField(json, 'received_by'),
      plateNo: json['plate_no'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      idempotencyKey: json['idempotency_key'] as String? ?? '',
      lines: [
        if (rawLines is List)
          for (final item in rawLines)
            if (item is Map<String, dynamic>)
              (
                variantId: intField(item, 'variant'),
                locationId: intField(item, 'location'),
                qty: decimalField(item, 'qty'),
              ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'receipt': receipt,
    'received_by': receivedBy,
    'plate_no': plateNo,
    'notes': notes,
    if (idempotencyKey.isNotEmpty) 'idempotency_key': idempotencyKey,
    'lines': [
      for (final line in lines)
        {
          'variant': line.variantId,
          'location': line.locationId,
          'qty': line.qty.toStringAsFixed(2),
        },
    ],
  };
}

/// The checker's verdict on one delivery: per line, good and damaged pieces.
class BodegaDeliveryConfirmation {
  const BodegaDeliveryConfirmation({required this.lines, this.notes = ''});

  final String notes;
  final List<({int lineId, double good, double damaged, String remarks})> lines;

  Map<String, dynamic> toJson() => {
    'notes': notes,
    'lines': [
      for (final line in lines)
        {
          'line': line.lineId,
          'good_qty': line.good.toStringAsFixed(2),
          'damaged_qty': line.damaged.toStringAsFixed(2),
          'remarks': line.remarks,
        },
    ],
  };
}
