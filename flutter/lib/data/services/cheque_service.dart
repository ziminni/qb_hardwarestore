import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/cheque.dart';
import 'package:dio/dio.dart';

/// Raised for anything the cheque screens must show a human.
///
/// [code] is the server's stable token (`CHEQUE_ALREADY_DECIDED`,
/// `CHEQUE_REASON_REQUIRED`, …) so the screen can branch on the fact while
/// [message] stays the sentence written for a person.
class ChequeServiceException implements Exception {
  const ChequeServiceException(this.message, {this.code});

  final String message;
  final String? code;

  /// A second decision on a cheque that is already settled (409). The caller
  /// must re-read the queue: its rows are now wrong about this cheque.
  bool get alreadyDecided => code == 'CHEQUE_ALREADY_DECIDED';

  @override
  String toString() => message;
}

/// The cheque queue and its two decisions, plus recording a cheque against a
/// utang (Phase 4 task B2, decision 18).
///
/// A cheque is NOT money: recording one writes a PENDING row and leaves
/// `balance_due` where it was. Only `clear/` moves the ledger, so this service
/// never posts an ordinary payment - that is `LedgerService.recordPayment`.
class ChequeService {
  ChequeService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const String chequesPath = '/api/v1/cheques/';

  static const String ledgerPaymentsPath = '/api/v1/ledger-payments/';

  /// Every cheque the server holds.
  ///
  /// Follows pagination rather than taking the first page, and is NOT narrowed by
  /// `?status=`: the queue's pending count and its status chips read the same
  /// list, so a server-side filter would either hide a row the "All" chip promises
  /// or need a second round trip to learn the count.
  Future<List<Cheque>> fetchCheques() async {
    try {
      return await _client.getAll<Cheque>(chequesPath, Cheque.fromJson);
    } on DioException catch (error) {
      throw ChequeServiceException(_messageFor(error));
    } on FormatException {
      // A page the client cannot parse is not "no cheques waiting": saying so
      // would show an empty, reassuring queue over a server it cannot read.
      throw const ChequeServiceException(
        'The cheque queue could not be read. Try again.',
      );
    }
  }

  /// The bank honoured the cheque: the utang is paid. Returns the updated row.
  Future<Cheque> clear(int chequeId) => _decide(chequeId, 'clear');

  /// The bank refused it ([reason] required): the debt stands. Returns the row.
  Future<Cheque> bounce(int chequeId, String reason) =>
      _decide(chequeId, 'bounce', reason: reason);

  /// Records a cheque against one open utang, through the ordinary payment route.
  ///
  /// The server answers 201 with the CHEQUE row, not a payment row, and does NOT
  /// move `balance_due` - a pending cheque is not money. Refusals keep their
  /// stable codes (`CHEQUE_NEEDS_CUSTOMER`, `CHEQUE_DETAILS_REQUIRED`,
  /// `PAYMENT_EXCEEDS_BALANCE`) and their server sentence, which names the
  /// missing fact or the amount still owed.
  Future<Cheque> recordChequeAgainstLedger({
    required int collectibleId,
    required double amount,
    required String chequeNumber,
    required String bank,
    required DateTime chequeDate,
  }) async {
    try {
      final response = await _client.post<dynamic>(
        ledgerPaymentsPath,
        data: {
          'collectible': collectibleId,
          'amount_paid': amount,
          // The wire code, not a label: the serializer validates `Payment.Method`.
          'payment_method': 'CHEQUE',
          'cheque_number': chequeNumber.trim(),
          'bank': bank.trim(),
          'cheque_date': isoDate(chequeDate),
        },
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw const FormatException('A cheque row was expected.');
      }
      return Cheque.fromJson(body);
    } on DioException catch (error) {
      throw ChequeServiceException(_messageFor(error));
    } on FormatException {
      throw const ChequeServiceException(
        'The cheque could not be read back. Check the queue before recording it again.',
      );
    }
  }

  /// `YYYY-MM-DD`: what `DateField` accepts for `cheque_date`.
  static String isoDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<Cheque> _decide(int chequeId, String action, {String? reason}) async {
    try {
      final response = await _client.post<dynamic>(
        '$chequesPath$chequeId/$action/',
        data: reason == null ? null : {'reason': reason.trim()},
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw const FormatException('A cheque row was expected.');
      }
      return Cheque.fromJson(body);
    } on DioException catch (error) {
      throw ChequeServiceException(_messageFor(error), code: _codeFor(error));
    } on FormatException {
      // The decision went through but its answer is unreadable. Saying "could not
      // be decided" would invite a second clear, so this names the real state.
      throw const ChequeServiceException(
        'The decision was sent, but the queue could not be read. Reload before deciding again.',
      );
    }
  }

  String? _codeFor(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['code'] is String) {
      return data['code'] as String;
    }
    return null;
  }

  String _messageFor(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) return 'You do not have access to cheques.';
    if (status == 404) return 'That cheque no longer exists. Reload the queue.';
    // Every refusal this server writes carries a `detail` written for a person,
    // and it names the precise fact ("already bounced", "needs a reason", "more
    // than the 472.00 still owed"). Dropping it for a generic sentence would hide
    // which of those it was, so it is used whenever it is there.
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    }
    return 'The cheque request could not be completed.';
  }
}
