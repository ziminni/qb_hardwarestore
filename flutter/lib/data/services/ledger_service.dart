import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/paged.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:dio/dio.dart';

/// Raised for anything the receivables screen must show to a human.
class LedgerServiceException implements Exception {
  const LedgerServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the collectibles ledger — the real receivables behind the sales screen — and posts
/// payments against it.
///
/// Decision 14 made the POS picker the single customer surface, so this service deliberately
/// exposes NO customer operations: it reads receivables and posts payments, nothing else.
/// Customer reads and writes live in `CustomerService`.
class LedgerService {
  LedgerService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const String ledgersPath = '/api/v1/ledgers/';

  static const String ledgerPaymentsPath = '/api/v1/ledger-payments/';

  /// Page size the server is configured with; the bound below is expressed in those units.
  static const int _maxPages = 40;

  /// Every open receivable, following pagination.
  ///
  /// Follows the pages rather than taking the first 50 for the same reason the POS picker
  /// does: a receivables screen that silently stops at the 50th debt is a screen that hides
  /// money, and `total_outstanding` on it would be a wrong number presented as a fact.
  Future<List<LedgerEntry>> fetchLedgers() async {
    final entries = <LedgerEntry>[];
    var page = 1;
    while (page <= _maxPages) {
      final response = await _get(page);
      entries.addAll(response.items);
      if (!response.hasMore) return entries;
      page++;
    }
    throw const LedgerServiceException(
      'The receivables list did not finish loading. Try again.',
    );
  }

  /// Posts one payment against one open receivable.
  ///
  /// The server moves `balance_due` and refuses overpayment with the stable
  /// `PAYMENT_EXCEEDS_BALANCE` code; that refusal is surfaced verbatim so the cashier
  /// sees the owed remainder, not a generic failure.
  Future<void> recordPayment({
    required int collectibleId,
    required double amountPaid,
    String paymentMethod = 'CASH',
    String? officialReceiptNo,
  }) async {
    try {
      await _client.post<void>(ledgerPaymentsPath, data: {
        'collectible': collectibleId,
        'amount_paid': amountPaid,
        'payment_method': paymentMethod,
        'official_receipt_no': ?officialReceiptNo,
      });
    } on DioException catch (error) {
      throw LedgerServiceException(_messageForPost(error));
    }
  }

  Future<Paged<LedgerEntry>> _get(int page) async {
    try {
      return await _client.getList<LedgerEntry>(
        ledgersPath,
        LedgerEntry.fromJson,
        queryParameters: {'page': page},
      );
    } on DioException catch (error) {
      throw LedgerServiceException(_messageFor(error));
    } on FormatException {
      // A page the client cannot parse is not "no receivables" — saying so would show a
      // cashier an empty, reassuring screen over a server they cannot read.
      throw const LedgerServiceException(
        'The receivables list could not be read. Try again.',
      );
    }
  }

  String _messageFor(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) return 'You do not have access to receivables.';
    return 'The receivables could not be loaded.';
  }

  String _messageForPost(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final data = error.response?.data;
    if (error.response?.statusCode == 400 && data is Map<String, dynamic>) {
      if (data['code'] == 'PAYMENT_EXCEEDS_BALANCE') {
        final detail = data['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        return 'That payment is more than the balance still owed.';
      }
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      for (final value in data.values) {
        if (value is List && value.isNotEmpty && value.first is String) {
          return value.first as String;
        }
      }
      return 'The payment was refused. Check the amount and try again.';
    }
    if (error.response?.statusCode == 401) {
      return 'Your session has expired. Sign in again.';
    }
    if (error.response?.statusCode == 403) {
      return 'You do not have access to record payments.';
    }
    return 'The payment could not be recorded.';
  }
}
