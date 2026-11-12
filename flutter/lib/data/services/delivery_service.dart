import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/delivery.dart';
import 'package:dio/dio.dart';

/// Raised when the delivery schedule cannot be read or a status move is
/// refused. [message] is safe to show.
class DeliveryServiceException implements Exception {
  const DeliveryServiceException(this.message, {this.code, this.status});

  final String message;

  /// The server's stable code, when it sent one (`DELIVERY_TRANSITION_INVALID`,
  /// `DELIVERY_REASON_REQUIRED`).
  final String? code;

  /// The status the server reports on a 409, so the row can be corrected from
  /// the answer instead of only being complained about.
  final String? status;

  bool get isTransitionRefused => code == 'DELIVERY_TRANSITION_INVALID';

  @override
  String toString() => message;
}

/// Reads the delivery schedule and moves a slip forward (Phase 5 B3 wire, F3
/// screens; ENDPOINTS.md §3.2).
///
/// The resource is read-only apart from three actions: a slip is created BY a
/// sale or an order, so there is no create, edit or delete here — the server
/// answers 405 for every role, Admin included.
///
/// A cashier-only caller sees only the slips THEY took (row scope on
/// `/transactions/`'s rule), so this class never widens or narrows the scope
/// itself: the server decides who may see what.
class DeliveryService {
  DeliveryService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const deliveriesPath = '/api/v1/deliveries/';

  /// Every slip matching the filters, soonest scheduled date first — the server
  /// orders the schedule as a work queue.
  ///
  /// The filters are the server's own, so a filtered read is the server's
  /// answer rather than a client-side narrowing of one page.
  Future<List<Delivery>> fetchAll({
    DeliveryStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      return await _client.getAll<Delivery>(
        deliveriesPath,
        Delivery.fromJson,
        queryParameters: {
          if (status != null) 'status': status.code,
          if (dateFrom != null) 'date_from': DeliveryDraft.wireDate(dateFrom),
          if (dateTo != null) 'date_to': DeliveryDraft.wireDate(dateTo),
        },
        maxPages: ApiClient.maxListPages,
      );
    } on DioException catch (error) {
      throw DeliveryServiceException(
        _message(error, 'The delivery schedule could not be loaded.'),
      );
    } on FormatException catch (error) {
      throw DeliveryServiceException(
        'The delivery schedule could not be loaded. (${error.message})',
      );
    } on TypeError {
      throw DeliveryServiceException(
        'The delivery schedule could not be loaded. (a row was not the shape '
        'this app expects)',
      );
    }
  }

  /// Scheduled → out for delivery.
  Future<Delivery> start(int id) => _move(id, 'start');

  /// Out for delivery → delivered. Terminal.
  Future<Delivery> deliver(int id) => _move(id, 'deliver');

  /// Scheduled or out for delivery → failed. [reason] is required: the trip
  /// happened and did not land the goods, so the trail has to say why.
  Future<Delivery> fail(int id, String reason) =>
      _move(id, 'fail', body: {'reason': reason});

  /// POSTs one of the three actions and reads the updated slip back.
  Future<Delivery> _move(int id, String action, {Object? body}) async {
    try {
      final response = await _client.post<dynamic>(
        '$deliveriesPath$id/$action/',
        data: body ?? const <String, dynamic>{},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw FormatException('A delivery is a single object.');
      }
      return Delivery.fromJson(data);
    } on DioException catch (error) {
      throw _refusal(error);
    } on FormatException catch (error) {
      throw DeliveryServiceException(
        'The delivery status could not be read. (${error.message})',
      );
    }
  }

  /// The server's own sentence first, then the code's fallback.
  ///
  /// A 409 carries the CURRENT status, which is why it is kept: the screen
  /// shows the refusal and re-reads, so a double click lands on the row the
  /// server actually holds instead of a stale button.
  DeliveryServiceException _refusal(DioException error) {
    final body = error.response?.data;
    String? code;
    String? status;
    if (body is Map<String, dynamic>) {
      final rawCode = body['code'];
      if (rawCode is String && rawCode.isNotEmpty) code = rawCode;
      final rawStatus = body['status'];
      if (rawStatus is String && rawStatus.isNotEmpty) status = rawStatus;
    }
    return DeliveryServiceException(
      _message(error, 'The delivery could not be updated.'),
      code: code,
      status: status,
    );
  }

  String _message(DioException error, String fallback) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) {
      return 'No permission to move a delivery. Ask a Store Manager, Admin or '
          'Stock Manager.';
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
      final code = data['code'];
      if (code is String) {
        final mapped = _codes[code];
        if (mapped != null) return mapped;
      }
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) return '${value.first}';
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return fallback;
  }

  /// Fallback sentences for a code that arrived without a `detail`. The server
  /// always sends one; these exist so a bare code still says something a clerk
  /// can act on.
  static const Map<String, String> _codes = {
    'DELIVERY_TRANSITION_INVALID':
        'This delivery has already moved on. The list has been refreshed.',
    'DELIVERY_REASON_REQUIRED':
        'A failed delivery needs a reason. Write why the goods did not land.',
    'INVALID_DELIVERY':
        'That delivery cannot be saved. Check the address, the contact and the '
        'date.',
  };
}
