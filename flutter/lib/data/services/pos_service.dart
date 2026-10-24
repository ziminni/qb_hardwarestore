import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/customer.dart';
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
  });

  final String method;
  final double amountTendered;
  final String referenceNo;

  Map<String, dynamic> toJson() => {
    'method': method,
    'amount_tendered': amountTendered,
    'reference_no': referenceNo,
  };
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
    );
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
}

/// One written sale line, read back from the transaction response.
class PosCheckoutLine {
  const PosCheckoutLine({
    required this.variantUomId,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  final int variantUomId;
  final double quantity;
  final double unitPrice;
  final double subtotal;
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

  /// A money field from the server (Decimal is serialized as a string), or null.
  static double? _amount(Object? value) =>
      value == null ? null : double.tryParse('$value');

  /// Two decimals, or a visible gap rather than a made-up zero.
  static String _money(double? value) =>
      value == null ? '(unknown)' : value.toStringAsFixed(2);
}
