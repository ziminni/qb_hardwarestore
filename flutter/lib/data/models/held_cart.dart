import 'package:client/data/models/json_field.dart';

/// One line of a parked (held) cart, read from `GET /api/v1/held-carts/`.
///
/// Field names follow the wire (`variant_uom`, `unit_price`) rather than being
/// prettified, so a rename on the server surfaces as a parse failure at the
/// boundary instead of a silently-zero line.
class HeldCartItem {
  const HeldCartItem({
    required this.id,
    required this.variantUom,
    required this.qty,
    required this.unitPrice,
  });

  factory HeldCartItem.fromJson(Map<String, dynamic> json) {
    return HeldCartItem(
      id: intField(json, 'id'),
      variantUom: intField(json, 'variant_uom'),
      qty: decimalField(json, 'qty'),
      unitPrice: decimalField(json, 'unit_price'),
    );
  }

  final int id;

  /// The **VariantUOM** id, not a ProductVariant id — same contract as the
  /// checkout payload (`HeldCartItemSerializer.variant_uom`).
  final int variantUom;

  final double qty;
  final double unitPrice;

  double get subtotal => qty * unitPrice;

  /// The POST shape for a line.
  ///
  /// `id` is sent but is `read_only` on `HeldCartItemSerializer`, so DRF ignores
  /// it on create; keeping it in the map makes one shape serve both a re-hold and
  /// a fresh line.
  Map<String, dynamic> toJson() => {
    'id': id,
    'variant_uom': variantUom,
    'qty': qty,
    'unit_price': unitPrice,
  };
}

/// A parked cart — Phase 3 of the cashier workflow.
///
/// The server assigns `cashier` from the authenticated request, so a held cart
/// belongs to the terminal's user and the client never chooses the actor.
class HeldCart {
  const HeldCart({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.cashierName,
    required this.notes,
    required this.items,
    required this.createdAt,
  });

  factory HeldCart.fromJson(Map<String, dynamic> json) {
    final customerName = json['customer_name'];
    return HeldCart(
      id: intField(json, 'id'),
      // Nullable: `HeldCart.customer` is `SET_NULL`, so a deleted customer
      // leaves a parked cart that is still resumable — just anonymous.
      customerId: json['customer'] == null
          ? null
          : intField(json, 'customer'),
      customerName: customerName is String && customerName.isNotEmpty
          ? customerName
          : null,
      cashierName: stringField(json, 'cashier_name'),
      notes: stringField(json, 'notes'),
      items: nestedList(json, 'items', HeldCartItem.fromJson),
      createdAt: DateTime.parse(stringField(json, 'created_at')),
    );
  }

  final int id;
  final int? customerId;
  final String? customerName;
  final String cashierName;
  final String notes;
  final List<HeldCartItem> items;
  final DateTime createdAt;

  /// What the list shows the cashier: who the cart is for.
  String get customerLabel => customerName ?? 'Walk-in';

  int get itemCount => items.length;

  double get total => items.fold(0, (sum, item) => sum + item.subtotal);
}
