import 'package:client/data/models/pick_up.dart';
import 'package:client/data/models/sale_discount.dart';

class PosCatalogItem {
  const PosCatalogItem({
    required this.variantUomId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.unit,
    required this.barcode,
    required this.conversionFactor,
    required this.unitPrice,
    required this.availableBaseStock,
    this.creditUnitPrice,
    this.categoryName = '',
    this.brandName = '',
    this.isWhole = false,
    this.storedAtName = '',
    this.isLowStock = false,
    this.imageUrl = '',
    this.allowDiscount = true,
  });
  final int variantUomId;
  final int variantId;
  final String productName;
  final String variantName;
  final String unit;
  final String barcode;
  final double conversionFactor;
  final double unitPrice;
  final double availableBaseStock;

  /// What this unit costs on utang (owner ruling): the server's computed
  /// `credit_selling_price`. Null/absent means no markup was configured, and the
  /// cash price is then the credit price too.
  final double? creditUnitPrice;

  /// The price a credit sale charges for this row, from the catalogue.
  double get creditPrice => creditUnitPrice ?? unitPrice;

  /// Shown on the till's product card and used by its category chips.
  final String categoryName;
  final String brandName;

  /// The product's photo URL (uploaded from Stocker → Products), or empty when
  /// no photo has been added yet.
  final String imageUrl;

  /// Where the shop keeps this product: the SERVER's pick-up point (Phase 5 B4).
  /// Empty when the row came from a server that does not send it, and the till
  /// then shows no badge rather than an invented one.
  final String storedAtName;

  /// Whether the shop ever discounts this product (owner ruling: cement is never
  /// discounted). False means the till must not offer a LINE discount on it, because
  /// the server refuses one with 400 `INVALID_DISCOUNT`.
  final bool allowDiscount;

  /// Derived from base stock and the server's per-variant threshold.
  final bool isLowStock;

  /// The SERVER's whole-number flag for this selling unit (Phase 1d).
  ///
  /// It replaces the client's list of whole unit words: a scan adds one straight
  /// to the cart only for a unit flagged whole, and everything else opens the
  /// quantity dialog. A row built without the flag is treated as measured, which
  /// is the safe direction (the cashier confirms a quantity).
  final bool isWhole;
  double get availableSaleQuantity => availableBaseStock / conversionFactor;
}

class PosCustomer {
  const PosCustomer({required this.id, required this.name, required this.type});
  final int id;
  final String name;
  final String type;
  factory PosCustomer.fromJson(Map<String, dynamic> json) => PosCustomer(
    id: json['id'] as int,
    name: json['name'] as String,
    type: json['customer_type'] as String? ?? 'WALK_IN',
  );
}

class PosCartLine {
  const PosCartLine({
    required this.variantUomId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.availableQuantity,
    this.creditUnitPrice,
    this.storedAtName = '',
    this.pickUp = const [],
    this.discount,
    this.allowDiscount = true,
    this.includeInDiscount = true,
  });
  final int variantUomId;
  final String productName;
  final String variantName;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double availableQuantity;

  /// The unit's utang price, carried from the catalogue so the cart can show
  /// what a credit sale would charge. Null reads as [unitPrice].
  final double? creditUnitPrice;

  /// This line's money at credit prices.
  double get creditTotal => quantity * (creditUnitPrice ?? unitPrice);

  /// The pick-up point the receipt prints as "Pick up at …" (Phase 5 B4).
  ///
  /// Empty means "the server did not say" — a legacy sale line, a held cart whose
  /// catalogue row is gone. The receipt then omits the caption rather than
  /// guessing a place the customer was never told.
  final String storedAtName;

  /// Which shelves this line actually LEFT, in pick order (Phase 9, decision 21
  /// §2). Empty on a sale rung before Phase 9, and the receipt then falls back
  /// to [storedAtName] — see `pickUpCaption`.
  final List<PickUpPart> pickUp;
  double get total => quantity * unitPrice;

  /// Whether this line may take a discount at all (owner ruling: cement is never
  /// discounted). Carried from the catalogue row like the name and the pick-up point,
  /// so the cart can hide the control instead of letting the server refuse the sale.
  final bool allowDiscount;

  /// Whether this line is ticked to share in a whole-sale discount.
  /// Defaults to true; the cashier can untick individual lines at checkout.
  final bool includeInDiscount;

  /// The discount the cashier gave on THIS line, or null when it has none.
  ///
  /// The server takes it off the line before it measures the sale-level discount,
  /// so the cart's own preview follows the same order (see [netTotal]).
  final PosDiscount? discount;

  /// What this line's own discount takes off, clamped to the line.
  double get discountAmount =>
      PosDiscountAmounts.forDiscount(total, discount).discountAmount;

  /// This line's money after its own discount.
  //
  // shortcut: a line PERCENT discount previews against the CASH line total even on a
  // credit sale; upgrade if utang sales with line discounts become common.
  double get netTotal => roundMoney(total - discountAmount);

  PosCartLine copyWith({double? quantity, bool? includeInDiscount}) =>
      PosCartLine(
        variantUomId: variantUomId,
        productName: productName,
        variantName: variantName,
        quantity: quantity ?? this.quantity,
        unit: unit,
        unitPrice: unitPrice,
        availableQuantity: availableQuantity,
        creditUnitPrice: creditUnitPrice,
        storedAtName: storedAtName,
        pickUp: pickUp,
        discount: discount,
        allowDiscount: allowDiscount,
        includeInDiscount: includeInDiscount ?? this.includeInDiscount,
      );

  /// This line with [discount] (null clears it).
  PosCartLine withDiscount(PosDiscount? discount) => PosCartLine(
    variantUomId: variantUomId,
    productName: productName,
    variantName: variantName,
    quantity: quantity,
    unit: unit,
    unitPrice: unitPrice,
    availableQuantity: availableQuantity,
    creditUnitPrice: creditUnitPrice,
    storedAtName: storedAtName,
    pickUp: pickUp,
    discount: discount,
    allowDiscount: allowDiscount,
    includeInDiscount: includeInDiscount,
  );

  Map<String, dynamic> toCheckoutJson() => {
    'variant_id': variantUomId,
    'qty': quantity,
    'unit_price': unitPrice,
  };
}

class PosReceipt {
  const PosReceipt({
    required this.reference,
    required this.officialReceiptNumber,
    required this.createdAt,
    required this.lines,
    required this.paymentMethod,
    required this.amountPaid,
    required this.total,
    this.payments = const [],
    this.discountAmount = 0,
    this.discountReason = '',
    this.vatableSales = 0,
    this.vatAmount = 0,
    this.vatRegistered = true,
    this.vatRate = 0,
    this.changeGiven = 0,
    this.deliveryFee = 0,
    this.paymentFee = 0,
    this.invoiceNo = '',
  });
  final String reference;
  final String officialReceiptNumber;
  final DateTime createdAt;
  final List<PosCartLine> lines;
  final String paymentMethod;

  /// The Invoice number written on the PAPER BIR Official Receipt the customer
  /// asked for (store-ops Phase 1), printed under the OS number.
  ///
  /// Empty on the ordinary Order-Slip-only sale, and the slip then prints
  /// nothing: an invented or blank invoice number on a BIR document would be a
  /// number the shop never wrote in its own booklet.
  final String invoiceNo;

  /// The FIRST tender's amount for a body that predates split payment. When
  /// [payments] is present the figures below come from the server's rows.
  final double amountPaid;

  /// What the customer actually owed: the server's `grand_total`, which is the NET
  /// of any discount (decision 18). Change is counted from here.
  final double total;

  /// Every tender the server stored (Phase 4 B2). Empty only for a sale written
  /// before split payment existed.
  final List<PosReceiptPayment> payments;

  /// What the server took off, and why (Phase 4 F4). Zero means no discount.
  final double discountAmount;
  final String discountReason;

  /// The VAT breakdown of [total], as the server computed it. Both zero when the
  /// store is not registered, and the receipt then says "Non-VAT".
  final double vatableSales;
  final double vatAmount;
  final bool vatRegistered;

  /// The rate from store settings, for the receipt's label only (`VAT (12%)`).
  /// Not used in arithmetic: the amounts above are the server's.
  final double vatRate;

  /// The lines added up before any discount, so the paper reconciles: subtotal less
  /// discount equals [total].
  double get grossTotal => lines.fold(0.0, (sum, line) => sum + line.total);

  /// Money in hand: every tender EXCEPT a cheque nobody has decided.
  ///
  /// A pending cheque does not pay the sale (decision 18). Counting it here would
  /// tell the cashier the debt is settled when the shop has received nothing.
  double get paidNow => payments.isEmpty
      ? amountPaid
      : payments
            .where((payment) => !payment.isPending)
            .fold(0.0, (sum, payment) => sum + payment.amount);

  /// Cheques waiting on the bank. Shown APART from [paidNow], never added to it.
  double get pendingChequeTotal => payments
      .where((payment) => payment.isPending)
      .fold(0.0, (sum, payment) => sum + payment.amount);

  /// Change handed back: the SERVER's `change_given` (QA High, Phase 4 close).
  ///
  /// It is money OUT of the drawer, so only the server can say how much: it knows the
  /// net it charged and every tender it stored. The till used to derive this itself
  /// and printed 0.00 for a 15.00 change on a split sale.
  final double changeGiven;

  /// The server's "Delivery charge" (Phase 5 B3, decision 18): part of [total],
  /// added AFTER the discount and never discounted. Zero for a sale the customer
  /// carried out, and the receipt then prints no line.
  final double deliveryFee;

  /// The sum of the fees charged on this sale's non-cash tenders, as the SERVER
  /// stored it. Already inside [total]; printed as its own line so the customer
  /// sees the fee and VAT as different things.
  final double paymentFee;

  /// What the customer still owes after the money in hand: the utang the pending
  /// cheque is holding open, or the shortfall on an underpaid sale.
  double get balanceDue => (total - paidNow).clamp(0, double.infinity);

  /// True when the sale went through more than one tender.
  bool get isSplit => payments.length > 1;
}

class PosCheckoutResult {
  const PosCheckoutResult({
    required this.transactionNumber,
    required this.officialReceiptNumber,
    required this.createdAt,
    required this.total,
  });
  final String transactionNumber;
  final String officialReceiptNumber;
  final DateTime createdAt;
  final double total;
}

/// One tender the server wrote, read back from the sale response (Phase 4 B2).
///
/// [status] is the server's own word: `CLEARED` for every tender that is money in
/// hand, and `PENDING`/`BOUNCED`/`CLEARED` for a cheque. The till never infers it.
class PosReceiptPayment {
  const PosReceiptPayment({
    required this.method,
    required this.amount,
    this.status = 'CLEARED',
    this.fee = 0,
    this.chequeNumber = '',
    this.bank = '',
    this.chequeDate,
    this.ledgerId,
    this.decidedAt,
    this.decisionReason = '',
  });

  final String method;
  final double amount;
  final String status;

  /// The fee this tender was charged, as the SERVER stored it (already inside
  /// `amount`). Read-only: recomputing it here would print a number that may
  /// disagree with what the shop actually collected.
  final double fee;
  final String chequeNumber;
  final String bank;
  final DateTime? chequeDate;

  /// The utang this cheque is holding open, when the server linked one.
  final int? ledgerId;
  final DateTime? decidedAt;
  final String decisionReason;

  bool get isCheque => method.toUpperCase() == 'CHEQUE';

  /// A cheque nobody has decided yet: NOT money, and never counted as paid.
  bool get isPending => isCheque && status.toUpperCase() == 'PENDING';

  factory PosReceiptPayment.fromJson(Map<String, dynamic> json) {
    final date = json['cheque_date'];
    final decided = json['decided_at'];
    final ledger = json['ledger'];
    return PosReceiptPayment(
      method: '${json['method'] ?? ''}',
      amount: double.tryParse('${json['amount_tendered']}') ?? 0,
      status: '${json['status'] ?? 'CLEARED'}',
      fee: double.tryParse('${json['fee'] ?? 0}') ?? 0,
      chequeNumber: '${json['cheque_number'] ?? ''}',
      bank: '${json['bank'] ?? ''}',
      chequeDate: date is String ? DateTime.tryParse(date) : null,
      ledgerId: ledger is int ? ledger : null,
      decidedAt: decided is String ? DateTime.tryParse(decided) : null,
      decisionReason: '${json['decision_reason'] ?? ''}',
    );
  }

  /// Tolerates a response that omits `payments`: the receipt then shows only the
  /// cart's single method, which is what such a sale was.
  static List<PosReceiptPayment> listFrom(Object? rows) {
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) PosReceiptPayment.fromJson(row),
    ];
  }
}
