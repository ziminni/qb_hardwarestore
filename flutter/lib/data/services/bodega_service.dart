import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/bodega.dart';
import 'package:dio/dio.dart';

/// Raised when a Bodega read or write fails. [message] is safe to show.
class BodegaServiceException implements Exception {
  const BodegaServiceException(this.message, {this.code});

  final String message;

  /// The server's stable code (`RELEASE_EXCEEDS_CLAIM`, `NO_BODEGA_CLAIM`, …).
  final String? code;

  bool get isConnectionFailure =>
      code == 'OFFLINE' ||
      message == 'Cannot connect to the BuildPro server.';

  @override
  String toString() => message;
}

/// `/api/v1/bodega/…` (decision 25; ENDPOINTS.md §3.8).
class BodegaService {
  BodegaService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const base = '/api/v1/bodega';

  Future<List<BodegaStockRow>> fetchStock() =>
      _list('$base/stock/', BodegaStockRow.fromJson, 'Bodega stock');

  Future<List<BodegaClaim>> fetchClaims({
    bool openOnly = true,
    String query = '',
  }) => _list(
    '$base/claims/',
    BodegaClaim.fromJson,
    'Bodega pick-ups',
    params: {
      'open': openOnly ? 'true' : 'false',
      if (query.isNotEmpty) 'q': query,
    },
  );

  Future<BodegaClaim> lookupClaim(String receipt) =>
      _guard('The receipt could not be looked up.', () async {
        final response = await _client.get<Map<String, dynamic>>(
          '$base/claims/lookup/',
          queryParameters: {'receipt': receipt},
        );
        return BodegaClaim.fromJson(_object(response.data));
      });

  Future<BodegaRelease> release(BodegaReleaseRequest request) =>
      _guard('The release could not be recorded.', () async {
        final response = await _client.post<Map<String, dynamic>>(
          '$base/releases/',
          data: request.toJson(),
          headers: request.idempotencyKey.isEmpty
              ? null
              : {'Idempotency-Key': request.idempotencyKey},
        );
        return BodegaRelease.fromJson(_object(response.data));
      });

  Future<List<BodegaRelease>> fetchReleases() => _guard(
    'The release log could not be read.',
    () => _client.getAll('$base/releases/', BodegaRelease.fromJson),
  );

  Future<List<BodegaDelivery>> fetchDeliveries({String status = ''}) => _guard(
    'The deliveries could not be read.',
    () => _client.getAll(
      '$base/deliveries/',
      BodegaDelivery.fromJson,
      queryParameters: {if (status.isNotEmpty) 'status': status},
    ),
  );

  Future<BodegaDelivery> confirmDelivery(
    int id,
    BodegaDeliveryConfirmation confirmation,
  ) => _guard('The delivery check could not be saved.', () async {
    final response = await _client.post<Map<String, dynamic>>(
      '$base/deliveries/$id/confirm/',
      data: confirmation.toJson(),
    );
    return BodegaDelivery.fromJson(_object(response.data));
  });

  /// Attaches the checker's photo to one waiting line
  /// (`POST …/deliveries/{id}/lines/{lineId}/photo/`); answers the delivery.
  Future<BodegaDelivery> uploadLinePhoto(
    int deliveryId,
    int lineId,
    List<int> bytes, {
    String filename = 'item.jpg',
  }) => _guard('The photo could not be saved.', () async {
    final response = await _client.post<Map<String, dynamic>>(
      '$base/deliveries/$deliveryId/lines/$lineId/photo/',
      data: FormData.fromMap({
        'photo': MultipartFile.fromBytes(bytes, filename: filename),
      }),
    );
    return BodegaDelivery.fromJson(_object(response.data));
  });

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
    String what, {
    Map<String, dynamic>? params,
  }) => _guard('$what could not be read.', () async {
    final response = await _client.get<dynamic>(path, queryParameters: params);
    final data = response.data;
    if (data is! List) throw const FormatException('Expected a list.');
    return [for (final row in data) fromJson(row as Map<String, dynamic>)];
  });

  static Map<String, dynamic> _object(Object? data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Expected an object.');
    }
    return data;
  }

  Future<T> _guard<T>(String fallback, Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw _failure(error, fallback);
    } on FormatException catch (error) {
      throw BodegaServiceException('$fallback (${error.message})');
    } on TypeError {
      throw BodegaServiceException(
        '$fallback (the reply was not the shape this app expects)',
      );
    }
  }

  static BodegaServiceException _failure(DioException error, String fallback) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const BodegaServiceException(
        'Cannot connect to the BuildPro server.',
      );
    }
    final status = error.response?.statusCode;
    if (status == 403) {
      return const BodegaServiceException(
        'Your account is not allowed to do this.',
        code: 'FORBIDDEN',
      );
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final code = data['code'];
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return BodegaServiceException(
          detail,
          code: code is String ? code : null,
        );
      }
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) {
          return BodegaServiceException('${value.first}');
        }
      }
    }
    return BodegaServiceException(fallback);
  }
}
