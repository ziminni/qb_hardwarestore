import 'package:client/data/models/json_field.dart';
import 'package:client/data/models/pick_up.dart';

/// Where a customer delivery stands (Phase 5 B3, decision 18).
///
/// Forward only: `scheduled → outForDelivery → delivered`, or `failed` from
/// either live state. The two finished states are terminal, so the screen offers
/// no action on them — and the server answers 409 if one is attempted anyway.
enum DeliveryStatus {
  scheduled('SCHEDULED', 'Scheduled'),
  outForDelivery('OUT_FOR_DELIVERY', 'Out for delivery'),
  delivered('DELIVERED', 'Delivered'),
  failed('FAILED', 'Failed');

  const DeliveryStatus(this.code, this.label);

  /// The server's code, and the value `?status=` filters by.
  final String code;

  /// What a reader sees. Sentence case, like every label in the app.
  final String label;

  /// Maps the wire code, failing loudly on one this build does not know: a
  /// delivery silently shown as "Scheduled" when the server said otherwise
  /// would offer Start on a trip already made.
  static DeliveryStatus fromWire(String value) {
    for (final status in values) {
      if (status.code == value) return status;
    }
    throw FormatException('Unknown delivery status "$value"');
  }

  bool get canStart => this == scheduled;
  bool get canDeliver => this == outForDelivery;
  bool get canFail => this == scheduled || this == outForDelivery;
  bool get isFinished => this == delivered || this == failed;
}

/// What the Deliver section of a form hands over: the wire's `delivery` object
/// (ENDPOINTS.md, *Delivery charge*).
///
/// A till sale, a held cart's completion and a sales order all take the same
/// shape, so it is built in one place: `{address, contact_name, contact_phone,
/// scheduled_date: "YYYY-MM-DD", fee}`. All but the fee are required by the
/// server; the form refuses to build a draft without them.
class DeliveryDraft {
  const DeliveryDraft({
    required this.address,
    required this.contactName,
    required this.contactPhone,
    required this.scheduledDate,
    this.fee = 0,
  });

  final String address;
  final String contactName;
  final String contactPhone;
  final DateTime scheduledDate;

  /// The "Delivery charge". Added AFTER the discount and never discounted, and
  /// money out of no stock — the server owns that arithmetic.
  final double fee;

  Map<String, dynamic> toJson() => {
    'address': address,
    'contact_name': contactName,
    'contact_phone': contactPhone,
    'scheduled_date': wireDate(scheduledDate),
    // 2 dp text: `10.005` is refused by the server, and a double can serialize
    // as 10.004999999999999 for a number nobody typed.
    'fee': fee.toStringAsFixed(2),
  };

  /// `YYYY-MM-DD`: the server parses this with `parse_date`, and a timestamp
  /// with a timezone on it is a date nobody wrote.
  static String wireDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }
}

/// One line of a delivery slip: what is being carried, in the selling unit.
///
/// [storedAtName] is B4's "Stored at". It is OPTIONAL here on purpose: the
/// backend adds it later, and a slip read before then must render with no
/// pick-up line rather than fail to parse.
class DeliveryItem {
  const DeliveryItem({
    required this.name,
    required this.unit,
    required this.qty,
    this.storedAtName,
    this.pickUp = const [],
  });

  final String name;
  final String unit;
  final double qty;

  /// Where the goods are picked up ("Bodega"), or null when the server did not
  /// send one.
  final String? storedAtName;

  /// Which shelves this line was picked from, in pick order (Phase 9, decision
  /// 21 §2): the driver is told the split, not just one place. Empty on a slip
  /// whose sale predates Phase 9, and the line then falls back to [storedAtName].
  final List<PickUpPart> pickUp;

  factory DeliveryItem.fromJson(Map<String, dynamic> json) {
    final storedAt = json['stored_at_name'];
    return DeliveryItem(
      name: stringField(json, 'name'),
      unit: stringField(json, 'unit'),
      qty: decimalField(json, 'qty'),
      storedAtName: storedAt is String && storedAt.trim().isNotEmpty
          ? storedAt.trim()
          : null,
      pickUp: nestedList(json, 'pick_up', PickUpPart.fromJson),
    );
  }
}

/// One row of `GET /api/v1/deliveries/` — the slip itself.
///
/// Read-only on the wire: a slip is created BY a sale or an order, so the only
/// writes are the three status moves. Every money figure is the server's.
class Delivery {
  const Delivery({
    required this.id,
    required this.deliveryNo,
    required this.saleId,
    required this.salesOrderId,
    required this.transactionNo,
    required this.orderNo,
    required this.customerId,
    required this.customerName,
    required this.address,
    required this.contactName,
    required this.contactPhone,
    required this.scheduledDate,
    required this.fee,
    required this.status,
    required this.failureReason,
    required this.items,
    required this.createdByName,
    required this.createdAt,
  });

  final int id;
  final String deliveryNo;
  final int? saleId;
  final int? salesOrderId;

  /// The sale's number, when this slip came from a till sale.
  final String transactionNo;

  /// The order's number, when it came from a sales order.
  final String orderNo;
  final int? customerId;
  final String customerName;
  final String address;
  final String contactName;
  final String contactPhone;
  final DateTime scheduledDate;
  final double fee;
  final DeliveryStatus status;
  final String failureReason;
  final List<DeliveryItem> items;
  final String createdByName;
  final DateTime? createdAt;

  /// What the document is called on screen and on paper.
  String get documentNo => deliveryNo;

  /// Who answers at the door: the contact when one was written, else the
  /// customer on the sale or order.
  String get recipient => contactName.isEmpty ? customerName : contactName;

  /// The sale or order this slip belongs to, for the details line.
  String get sourceLabel {
    if (transactionNo.isNotEmpty) return 'Sale $transactionNo';
    if (orderNo.isNotEmpty) return 'Order $orderNo';
    return 'No sale or order on file';
  }

  factory Delivery.fromJson(Map<String, dynamic> json) {
    final rows = json['items'];
    return Delivery(
      id: intField(json, 'id'),
      deliveryNo: stringField(json, 'delivery_no'),
      saleId: json['sale'] is int ? json['sale'] as int : null,
      salesOrderId: json['sales_order'] is int
          ? json['sales_order'] as int
          : null,
      transactionNo: json['transaction_no'] as String? ?? '',
      orderNo: json['order_no'] as String? ?? '',
      customerId: json['customer'] is int ? json['customer'] as int : null,
      customerName: json['customer_name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      contactName: json['contact_name'] as String? ?? '',
      contactPhone: json['contact_phone'] as String? ?? '',
      scheduledDate: _dateField(json, 'scheduled_date'),
      fee: decimalField(json, 'fee'),
      status: DeliveryStatus.fromWire(stringField(json, 'status')),
      failureReason: json['failure_reason'] as String? ?? '',
      items: rows is List
          ? [
              for (final row in rows)
                if (row is Map<String, dynamic>) DeliveryItem.fromJson(row),
            ]
          : const [],
      createdByName: json['created_by_name'] as String? ?? '',
      createdAt: nullableDateField(json, 'created_at'),
    );
  }

  /// `scheduled_date` is a plain `YYYY-MM-DD`; `DateTime.parse` reads it as
  /// midnight local, which is the day the driver reads.
  static DateTime _dateField(Map<String, dynamic> json, String key) {
    final parsed = nullableDateField(json, key);
    if (parsed == null) {
      throw FormatException('Missing required date field "$key"');
    }
    return parsed;
  }
}
