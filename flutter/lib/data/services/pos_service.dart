import 'dart:math';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/pos_transaction.dart' show PosReceiptPayment;
import 'package:client/data/models/sale_discount.dart';
import 'package:dio/dio.dart';

/// One line of a checkout request.
///
/// [variantUomId] is sent as the payload's `variant_id`. The name is the API's, not
/// ours, and it is a **VariantUOM** id: `process_sale` does
/// `SalesItem.objects.create(variant_uom_id=item_id)` and then resolves
/// `VariantUOM.objects.filter(pk=item_id)` to decide which variant to deduct stock
/// from. Sending a ProductVariant id, or anything synthesized, deducts from the wrong
/// unit or none. See decision 06 section 2.
class PosCheckoutItem {
  const PosCheckoutItem({
    required this.variantUomId,
    required this.quantity,
    required this.unitPrice,
  });

  final int variantUomId;
  final double quantity;
  final double unitPrice;

  Map<String, dynamic> toJson() => {
    'variant_id': variantUomId,
    'qty': quantity,
    'unit_price': unitPrice,
  };
}

/// One tender against a sale. A sale may be paid by several.
class PosCheckoutPayment {
  const PosCheckoutPayment({
    required this.method,
    required this.amountTendered,
    this.referenceNo = '',
    this.chequeNumber = '',
    this.bank = '',
    this.chequeDate,
  });

  final String method;
  final double amountTendered;
  final String referenceNo;

  /// The three facts a CHEQUE must carry (Phase 4 B2, decision 18). Ignored for
  /// every other method, because only a cheque becomes a row a manager decides.
  final String chequeNumber;
  final String bank;
  final DateTime? chequeDate;

  bool get isCheque => method == 'CHEQUE';

  Map<String, dynamic> toJson() => {
    'method': method,
    // A 2 dp string: DRF sends and takes Decimals as strings, and a double can
    // serialize as 7.999999999999999 for money nobody typed.
    'amount_tendered': amountTendered.toStringAsFixed(2),
    'reference_no': referenceNo,
    if (isCheque) ...{
      'cheque_number': chequeNumber,
      'bank': bank,
      'cheque_date': formatWireDate(chequeDate),
    },
  };
}

/// `2026-11-20` for a date the server parses with `parse_date`, or empty.
String formatWireDate(DateTime? date) {
  if (date == null) return '';
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

/// A completed sale, read from the POST response.
///
/// Decision 06 section 1: the response to `POST /api/v1/transactions/` **is** the
/// finished transaction, with `items`, `payments` and `receipt` nested. The receipt
/// screen therefore needs no second fetch — and the client must not re-read by id,
/// which would be a second round trip for data it already holds.
class PosCheckoutResult {
  const PosCheckoutResult({
    required this.id,
    required this.transactionNo,
    required this.orNumber,
    required this.transDate,
    required this.grandTotal,
    this.lines = const [],
    this.payments = const [],
    this.discountAmount = 0,
    this.discountReason = '',
    this.vatableSales = 0,
    this.vatAmount = 0,
    this.vatRegistered = true,
    this.changeGiven = 0,
    this.deliveryFee = 0,
  });

  factory PosCheckoutResult.fromJson(Map<String, dynamic> json) {
    final receipt = json['receipt'];
    final receiptMap = receipt is Map<String, dynamic> ? receipt : const {};
    final orNumber = receiptMap['or_number'];
    return PosCheckoutResult(
      id: json['id'] as int,
      transactionNo: json['transaction_no'] as String,
      // A sale whose receipt is missing is a contract break, and the receipt number
      // is the customer's proof of purchase — better to fail loudly than to print a
      // receipt with a blank OR number.
      orNumber: orNumber is String && orNumber.isNotEmpty
          ? orNumber
          : (throw FormatException(
              'The server did not return an official receipt number.',
            )),
      transDate: DateTime.parse(json['trans_date'] as String),
      grandTotal: double.parse('${json['grand_total']}'),
      lines: _linesFrom(json['items']),
      // Phase 4 B2: every tender the server wrote, so a receipt can show a split
      // sale and a cheque that is PENDING rather than paid.
      payments: PosReceiptPayment.listFrom(json['payments']),
      // Phase 4 B1: the discount and the VAT split are the SERVER's numbers, so the
      // receipt prints what was actually charged. A body from before B1 has none of
      // them, and each falls back to the pre-discount, VAT-not-split reading.
      discountAmount: _moneyOrZero(json['discount_amount']),
      discountReason: json['discount_reason'] is String
          ? json['discount_reason'] as String
          : '',
      vatableSales: _moneyOrZero(json['vatable_sales']),
      vatAmount: _moneyOrZero(json['vat_amount']),
      vatRegistered: json['vat_registered'] is bool
          ? json['vat_registered'] as bool
          : true,
      // QA High (Phase 4 close): the change the cashier handed back, decided by the
      // server from the tenders it STORED. The receipt prints this number and never
      // recomputes it from the payment rows.
      changeGiven: _moneyOrZero(json['change_given']),
      // Phase 5 B3: the "Delivery charge" the server added AFTER the discount.
      // A body from before B3 has none, and the receipt then prints no line.
      deliveryFee: _moneyOrZero(json['delivery_fee']),
    );
  }

  static double _moneyOrZero(Object? value) {
    if (value == null) return 0;
    return double.tryParse('$value') ?? 0;
  }

  /// Reads the written lines, tolerating a response that omits `items`.
  ///
  /// A missing list is NOT a contract break worth throwing on: the receipt has
  /// the server's grand total either way, and the cart's snapshot is a faithful
  /// fallback for names and quantities. Throwing here would turn a cosmetic
  /// omission into a lost sale that DID happen.
  static List<PosCheckoutLine> _linesFrom(Object? items) {
    if (items is! List) return const [];
    final lines = <PosCheckoutLine>[];
    for (final item in items) {
      if (item is! Map) continue;
      final variantUomId = item['variant_uom'];
      if (variantUomId is! int) continue;
      lines.add(
        PosCheckoutLine(
          variantUomId: variantUomId,
          quantity: double.parse('${item['qty']}'),
          unitPrice: double.parse('${item['unit_price']}'),
          subtotal: double.parse('${item['subtotal']}'),
          // Phase 5 B4: the server names the pick-up point on every sale line, so
          // the receipt prints it from the STORED sale rather than from today's
          // catalogue. An older body omits it, and the receipt then says nothing.
          storedAtName: item['stored_at_name'] is String
              ? item['stored_at_name'] as String
              : '',
        ),
      );
    }
    return lines;
  }

  final int id;
  final String transactionNo;
  final String orNumber;
  final DateTime transDate;
  final double grandTotal;

  /// The sale's lines exactly as the SERVER wrote them.
  ///
  /// The server prices every line from `VariantUOM.default_selling_price` and
  /// converts the selling quantity by `conversion_factor`, so a client-computed
  /// line total is only a preview. The receipt prints from here.
  final List<PosCheckoutLine> lines;

  /// What the server took off the gross (decision 18). Zero when none was given.
  final double discountAmount;

  /// Why the discount was given, as the cashier wrote it.
  final String discountReason;

  /// The VAT breakdown of the NET. Both are zero when the store is not registered.
  final double vatableSales;
  final double vatAmount;
  final bool vatRegistered;

  /// The tenders exactly as the server stored them, in order. Empty only for a
  /// body that predates B2, in which case the receipt falls back to the single
  /// method and amount the cart recorded.
  final List<PosReceiptPayment> payments;

  /// Change handed back at the drawer (QA High, Phase 4 close). Money OUT, so the
  /// server decides it - the till only prints it.
  final double changeGiven;

  /// The "Delivery charge" the server added to `grand_total` after the discount
  /// (Phase 5 B3, decision 18). Zero means this sale was not delivered.
  final double deliveryFee;
}

/// One written sale line, read back from the transaction response.
class PosCheckoutLine {
  const PosCheckoutLine({
    required this.variantUomId,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.storedAtName = '',
  });

  final int variantUomId;
  final double quantity;
  final double unitPrice;
  final double subtotal;

  /// The product's pick-up point as the SALE recorded it (Phase 5 B4). Empty on
  /// a body written before B4.
  final String storedAtName;
}

/// One line of a sales order as the TILL needs it (Phase 7 F2, decision 19).
///
/// Not reused from `sale_transaction.dart`: `fulfil/` keys a line by its
/// `SalesOrderItem` pk (`order_line`), which the sales-side model does not carry,
/// and the till is the only caller that sends one.
class PosOpenOrderLine {
  const PosOpenOrderLine({
    required this.id,
    required this.variantUomId,
    required this.qty,
    required this.unitPrice,
    required this.remainingQty,
    this.availableQty,
    this.fulfilledQty = 0,
  });

  /// The order line's pk - what `fulfil/` calls `order_line`.
  final int id;
  final int variantUomId;

  /// What was ordered, and the price the customer agreed to. The till charges
  /// this price: it is READ-ONLY at the counter.
  final double qty;
  final double unitPrice;

  /// What is still owed on this line (server arithmetic).
  final double remainingQty;

  /// Sellable stock in this line's unit right now, or null when the server did
  /// not say. A live hint only: nothing is reserved for an order.
  final double? availableQty;

  /// What has already been rung. Zero means this order has never been fulfilled
  /// and so carries the agreed delivery fee on its next sale.
  final double fulfilledQty;

  /// "Enough in stock" / "Short by N", or null when the wire sent no hint.
  String? get stockHint {
    final available = availableQty;
    if (available == null) return null;
    final shortfall = remainingQty - available;
    if (shortfall <= 0) return 'Enough in stock';
    return 'Short by ${_units(shortfall)}';
  }

  static String _units(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  /// A Decimal from the wire (DRF sends strings), or null when absent.
  static double? _amount(Object? value) =>
      value == null ? null : double.tryParse('$value');

  factory PosOpenOrderLine.fromJson(
    Map<String, dynamic> json,
  ) => PosOpenOrderLine(
    id: json['id'] as int,
    variantUomId: json['variant_uom'] as int,
    qty: _amount(json['qty']) ?? 0,
    unitPrice: _amount(json['unit_price']) ?? 0,
    // A body from before B1 has neither column: what was ordered is still owed.
    remainingQty: _amount(json['remaining_qty']) ?? _amount(json['qty']) ?? 0,
    availableQty: _amount(json['available_qty']),
    fulfilledQty: _amount(json['fulfilled_qty']) ?? 0,
  );
}

/// A sales order the till may ring (Phase 7 F2, decision 19 #3/#4).
class PosOpenOrder {
  const PosOpenOrder({
    required this.id,
    required this.number,
    required this.customerId,
    required this.status,
    required this.lines,
  });

  final int id;
  final String number;
  final int customerId;

  /// The EFFECTIVE status the server sent: a legacy PROCESSING/READY row reads
  /// as CONFIRMED, and only CONFIRMED/PARTIAL can still be rung.
  final String status;
  final List<PosOpenOrderLine> lines;

  static const openStatuses = {'CONFIRMED', 'PARTIAL'};

  bool get isOpen => openStatuses.contains(status);

  /// True before anything was rung: the agreed delivery fee is charged on the
  /// FIRST fulfilment and on no later one.
  bool get hasNothingFulfilled => lines.every((line) => line.fulfilledQty == 0);

  /// What the goods still come to - not the total, because the delivery fee
  /// lives on its own slip and is never discounted.
  double get remainingTotal => lines.fold<double>(
    0,
    (sum, line) => sum + line.remainingQty * line.unitPrice,
  );

  factory PosOpenOrder.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw FormatException('Missing required list field "items"');
    }
    return PosOpenOrder(
      id: json['id'] as int,
      number: json['order_no'] as String,
      customerId: json['customer'] as int,
      status: json['status'] as String,
      lines: [
        for (final item in items)
          PosOpenOrderLine.fromJson(item as Map<String, dynamic>),
      ],
    );
  }
}

/// One line the till sends to `POST /sales-orders/{id}/fulfil/`.
class PosFulfilLine {
  const PosFulfilLine({required this.orderLineId, required this.quantity});

  final int orderLineId;
  final double quantity;

  Map<String, dynamic> toJson() => {'order_line': orderLineId, 'qty': quantity};
}

/// Raised when a sale cannot be completed. [message] is safe to show a cashier.
class PosServiceException implements Exception {
  const PosServiceException(
    this.message, {
    this.code,
    this.shortfall,
    this.variantId,
    this.limit,
    this.outstanding,
  });

  final String message;

  /// The server's stable machine-readable code, when it sent one.
  final String? code;

  /// How far short the sale was, when the server said so.
  final double? shortfall;

  /// The variant the server blamed, when it said stock was short.
  ///
  /// Decision 06 section 3 requires the client to "identify the offending line". The
  /// server names a **variant**, while the cart is keyed by `VariantUom`, so this is
  /// what the viewmodel maps onto a cart row. Null when the server did not say - and
  /// a caller must then point at nothing rather than guess.
  final int? variantId;

  /// The customer's credit limit, when the server refused the sale for credit.
  final double? limit;

  /// What that customer already owed, when the server refused for credit.
  final double? outstanding;

  /// True only when the server explicitly said stock was short.
  ///
  /// Deliberately NOT inferred from the status code: a 400 can also mean a bad
  /// customer, and a 500 means the server broke. Telling a cashier to reduce a
  /// quantity because the server 500'd would be a lie about the cause.
  bool get isInsufficientStock => code == 'INSUFFICIENT_STOCK';

  @override
  String toString() => message;
}

/// Completes a sale through the POS backend.
///
/// The last step of the Cashier journey (decision 01), and the only write in it that
/// moves money. `process_sale` does all of this inside one `transaction.atomic()` on
/// the server: FIFO stock deduction, payment allocation, official-receipt generation,
/// and a `CollectibleLedger` posting when the sale is underpaid.
///
/// Two consequences the caller must respect, both from decision 06:
///
/// * A failure rolls back **wholesale**, so the cart must never be cleared
///   optimistically — it is cleared only after a successful response.
/// * Insufficient stock is an *expected* outcome, not a crash. It arrives as a 400
///   carrying [PosServiceException.isInsufficientStock] and the shortfall.
class PosService {
  PosService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const transactionsPath = '/api/v1/transactions/';
  static const customersPath = '/api/v1/customers/';
  static const salesOrdersPath = '/api/v1/sales-orders/';
  static const deliveriesPath = '/api/v1/deliveries/';

  /// The customer id to send for an anonymous sale.
  ///
  /// Decision 06 section 2: a walk-in sale **cannot omit** the customer.
  /// `SalesTransaction.customer` is `FK(PROTECT)` with no `null=True`, and the view
  /// reads `validated_data['customer'].id` without a fallback - so an anonymous sale
  /// still sends an id, and the id it sends is the Walk-in Customer record that
  /// `seed_demo` creates.
  ///
  /// Fails loudly rather than picking another customer: sending a real customer's id
  /// would post the utang to their account.
  Future<int> fetchWalkInCustomerId() async {
    try {
      final page = await _client.getList<Customer>(
        customersPath,
        Customer.fromJson,
      );
      for (final customer in page.items) {
        if (customer.name.trim().toLowerCase() ==
            Customer.walkInName.toLowerCase()) {
          return customer.id;
        }
      }
    } on DioException catch (error) {
      throw _failureFor(error);
    }
    throw const PosServiceException(
      'The demo data has no Walk-in Customer, so an anonymous sale cannot be '
      'recorded. Run the seed command first.',
    );
  }

  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
    String? idempotencyKey,
    PosDiscount? discount,
    String? discountApproval,
    DeliveryDraft? delivery,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        transactionsPath,
        headers: _idempotencyHeaders(idempotencyKey),
        data: {
          'customer': customerId,
          // `cashier` is deliberately absent: the serializer is read-only for it and
          // the server assigns the actor from the authenticated request. A client
          // that could set it could attribute a sale to another cashier.
          'source': source,
          'items': [for (final item in items) item.toJson()],
          'payments': [for (final payment in payments) payment.toJson()],
          // Decision 18: the discount is checked and applied on the server, and a
          // discount above the cap also needs the manager's one-time approval token.
          if (discount != null) 'discount': discount.toJson(),
          if (discountApproval != null && discountApproval.isNotEmpty)
            'discount_approval': discountApproval,
          // Phase 5 B3: the delivery object is optional; when it is present the
          // server writes the slip and adds its fee to `grand_total` AFTER the
          // discount (ENDPOINTS.md, *Delivery charge*).
          if (delivery != null) 'delivery': delivery.toJson(),
        },
      );
      final data = response.data;
      if (data == null) {
        throw const PosServiceException(
          'The server did not return the completed sale.',
        );
      }
      return PosCheckoutResult.fromJson(data);
    } on DioException catch (error) {
      throw _failureFor(error);
    }
  }

  /// The orders the counter may still ring: CONFIRMED or PARTIAL, with a line
  /// left to ring (Phase 7 F2, decision 19 #3).
  ///
  /// Filtered HERE, on the status the wire carries, rather than with `?status=`:
  /// the server reports the EFFECTIVE status, so a legacy PROCESSING/READY row is
  /// a live order and a column filter would hide it.
  Future<List<PosOpenOrder>> fetchOpenOrders() async {
    try {
      // Every page: an order taken three weeks ago is still CONFIRMED, so page 1
      // of the newest orders is not "the open ones".
      final rows = await _client.getAll<PosOpenOrder>(
        salesOrdersPath,
        PosOpenOrder.fromJson,
      );
      return [
        for (final row in rows)
          if (row.isOpen && row.lines.any((line) => line.remainingQty > 0)) row,
      ];
    } on DioException catch (error) {
      throw _failureFor(error);
    }
  }

  /// The delivery fee the FIRST fulfilment must charge, or null when the order
  /// has no slip (Phase 7 B4: the fee moves onto the sale once).
  ///
  /// A slip this cashier may not read (another till took the order) answers 404
  /// under the row scope, and that is not an error at the counter: the till then
  /// cannot PREVIEW the charge, while the server still bills it exactly once.
  Future<double?> fetchOrderDeliveryFee(int orderId) async {
    try {
      final response = await _client.get<dynamic>(
        deliveriesPath,
        queryParameters: {'sales_order': orderId},
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) return null;
      final results = body['results'];
      if (results is! List || results.isEmpty) return null;
      final slip = results.first;
      return slip is Map<String, dynamic> ? _amount(slip['fee']) : null;
    } on DioException {
      return null;
    }
  }

  /// Rings what is left of an order into a real sale (Phase 7 B4).
  ///
  /// The response IS the finished transaction, receipt and all, exactly as on
  /// checkout - so the receipt path is shared and this method adds no second one.
  /// No `delivery` is ever sent: the slip belongs to the order and the server
  /// refuses one on every fulfilment.
  Future<PosCheckoutResult> fulfilOrder({
    required int orderId,
    required List<PosFulfilLine> lines,
    required List<PosCheckoutPayment> payments,
    String? idempotencyKey,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '$salesOrdersPath$orderId/fulfil/',
        headers: _idempotencyHeaders(idempotencyKey),
        data: {
          'lines': [for (final line in lines) line.toJson()],
          'payments': [for (final payment in payments) payment.toJson()],
        },
      );
      final data = response.data;
      if (data == null) {
        throw const PosServiceException(
          'The server did not return the completed sale.',
        );
      }
      return PosCheckoutResult.fromJson(data);
    } on DioException catch (error) {
      throw _failureFor(error);
    }
  }

  /// 32 hex characters from a CSPRNG: one sale attempt's `Idempotency-Key`.
  ///
  /// Well inside the server's 64-character cap, and NOT a UUID dependency: the
  /// server only requires uniqueness per cashier, and `Random.secure()` gives that
  /// without adding a package.
  static String newIdempotencyKey() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// The `Idempotency-Key` header, or null when this attempt carries no key.
  ///
  /// ENDPOINTS.md *Idempotency*: a repeat of (cashier, key) with the same body
  /// answers 200 and the ORIGINAL transaction; the same key with a different body
  /// answers 409. The header is therefore per ATTEMPT - the viewmodel owns the
  /// key and reuses it across retries - never a per-client constant.
  static Map<String, String>? _idempotencyHeaders(String? key) {
    if (key == null || key.isEmpty) return null;
    return {'Idempotency-Key': key};
  }

  /// Maps a transport failure onto something a cashier can act on.
  ///
  /// A malformed body is NOT caught here: it surfaces as a `FormatException` from
  /// [PosCheckoutResult.fromJson], matching the convention the inventory service
  /// already set, because a contract break must fail loudly rather than be reported
  /// as a retryable network problem.
  PosServiceException _failureFor(DioException error) {
    final response = error.response;
    if (response != null) {
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final code = body['code'];
        if (code is String && code == 'INSUFFICIENT_STOCK') {
          final detail = body['detail'];
          final shortfall = body['shortfall'];
          final variantId = body['variant_id'];
          return PosServiceException(
            detail is String && detail.isNotEmpty
                ? detail
                : 'There is not enough stock to complete this sale.',
            code: code,
            shortfall: shortfall == null ? null : double.tryParse('$shortfall'),
            variantId: variantId is int ? variantId : null,
          );
        }
        if (code is String && code == 'CREDIT_LIMIT_EXCEEDED') {
          // Phase 1 Task 2 answers with three Decimal strings and no prose worth
          // printing, so the cashier's instruction is assembled here: what the
          // customer owes, what this sale adds, and the ceiling it breaks.
          final limit = _amount(body['limit']);
          final outstanding = _amount(body['outstanding']);
          final shortfall = _amount(body['shortfall']);
          return PosServiceException(
            'Credit limit exceeded: outstanding ${_money(outstanding)} + this '
            'sale ${_money(shortfall)} > limit ${_money(limit)}.',
            code: code,
            limit: limit,
            outstanding: outstanding,
            shortfall: shortfall,
          );
        }
        if (code is String && code == 'WHOLE_UNIT_QUANTITY') {
          // Phase 1d: the server refuses a fractional count of a unit it counts in
          // ones. Its detail names the line, the product and the unit, which is
          // more than this client can say — but a body that lost its prose must
          // still read as "change the quantity", not as "try again".
          final detail = body['detail'];
          return PosServiceException(
            detail is String && detail.isNotEmpty ? detail : _wholeUnitMessage,
            code: code,
          );
        }
        if (code is String && code == 'IDEMPOTENCY_KEY_REUSED') {
          // A 409 means this key was already spent on a DIFFERENT sale. Saying so
          // plainly stops a cashier retrying into the same wall - and stops them
          // believing the basket in front of them was rung up.
          return const PosServiceException(
            'This attempt was already used for a different sale. Start the '
            'payment again.',
            code: 'IDEMPOTENCY_KEY_REUSED',
          );
        }
        final detail = body['detail'];
        if (detail is String && detail.isNotEmpty) {
          return PosServiceException(
            detail,
            code: code is String ? code : null,
          );
        }
      }
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return const PosServiceException(
          'Cannot connect to the BuildPro server.',
        );
      default:
        return const PosServiceException(
          'The sale could not be completed. Try again.',
        );
    }
  }

  /// What a cashier reads when a whole-unit refusal arrives without prose.
  static const _wholeUnitMessage =
      'That unit is sold in whole numbers, so the quantity must be a whole '
      'number. Change it and try again.';

  /// A money field from the server (Decimal is serialized as a string), or null.
  static double? _amount(Object? value) =>
      value == null ? null : double.tryParse('$value');

  /// Two decimals, or a visible gap rather than a made-up zero.
  static String _money(double? value) =>
      value == null ? '(unknown)' : value.toStringAsFixed(2);
}
