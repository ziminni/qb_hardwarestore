import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/held_cart.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:dio/dio.dart';

/// Raised when the held-cart API cannot be reached or answers unexpectedly.
///
/// [message] is safe to show a cashier.
class HeldCartServiceException implements Exception {
  const HeldCartServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parked carts — Phase 3 of the cashier workflow.
///
/// A held cart is *only* a parked basket: nothing has been deducted, no sale
/// exists and no money has moved. Two consequences the caller must respect:
///
/// * **Void is a plain DELETE** and destroys the parked basket. It is the one
///   irreversible action here, so the page confirms before calling it.
/// * **Complete is not implemented as "resume then pay"** — the server's
///   `complete` action runs `process_sale` and deletes the cart inside one
///   transaction, so it must never be retried blindly after a timeout.
class HeldCartService {
  HeldCartService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const heldCartsPath = '/api/v1/held-carts/';

  /// How many pages to read before giving up. 10 x DRF's `PAGE_SIZE` (50) = 500
  /// parked carts, far past what a counter accumulates between shifts, so hitting
  /// it means the API is misbehaving rather than that the list is long.
  static const _maxPages = 10;

  /// Every parked cart, newest first (the model's default ordering).
  ///
  /// Follows pagination because [ApiClient.getList] returns ONE page: holding a
  /// cart past page one would otherwise be invisible, and an invisible parked
  /// cart is a customer's basket the cashier can never resume or void.
  Future<List<HeldCart>> fetchAll() async {
    try {
      final all = <HeldCart>[];
      var page = 1;
      while (true) {
        final result = await _client.getList<HeldCart>(
          heldCartsPath,
          HeldCart.fromJson,
          queryParameters: {'page': page},
        );
        all.addAll(result.items);
        if (!result.hasMore) return all;
        page++;
        if (page > _maxPages) {
          throw const FormatException('The held cart list did not end.');
        }
      }
    } on DioException catch (error) {
      throw HeldCartServiceException(_message(error));
    } on FormatException {
      throw const HeldCartServiceException(
        'The held carts could not be read. Try again.',
      );
    }
  }

  /// Parks a basket. `cashier` is deliberately absent: the serializer is
  /// read-only for it and the server assigns the actor from the request.
  Future<HeldCart> hold({
    int? customerId,
    String notes = '',
    required List<HeldCartItem> items,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        heldCartsPath,
        data: {
          'customer': customerId,
          'notes': notes,
          'items': [for (final item in items) item.toJson()],
        },
      );
      final data = response.data;
      if (data == null) {
        throw const HeldCartServiceException(
          'The server did not return the held cart.',
        );
      }
      return HeldCart.fromJson(data);
    } on DioException catch (error) {
      throw HeldCartServiceException(_message(error));
    } on FormatException {
      throw const HeldCartServiceException(
        'The server returned a held cart this app cannot read.',
      );
    }
  }

  /// Discards a parked basket. Irreversible — the items are gone.
  Future<void> voidCart(int cartId) async {
    try {
      await _client.dio.delete<void>('$heldCartsPath$cartId/');
    } on DioException catch (error) {
      throw HeldCartServiceException(_message(error));
    }
  }

  /// Sells a parked basket: the server deducts stock, writes the sale, prints an
  /// official receipt and deletes the cart, all inside one transaction.
  ///
  /// [idempotencyKey] makes a retry SAFE. The cart is deleted by the successful
  /// call, so after a dropped response there is nothing left to resolve by id —
  /// replaying the same key is the only way to find out whether the sale happened
  /// (200 with the original) instead of guessing (404).
  Future<Map<String, dynamic>> complete(
    int cartId, {
    required List<PosCheckoutPayment> payments,
    String? idempotencyKey,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '$heldCartsPath$cartId/complete/',
        headers: idempotencyKey == null || idempotencyKey.isEmpty
            ? null
            : {'Idempotency-Key': idempotencyKey},
        data: {
          'payments': [for (final payment in payments) payment.toJson()],
        },
      );
      final data = response.data;
      if (data == null) {
        throw const HeldCartServiceException(
          'The server did not return the completed sale.',
        );
      }
      return data;
    } on DioException catch (error) {
      throw HeldCartServiceException(_message(error));
    }
  }

  /// Maps a transport failure onto something a cashier can act on.
  String _message(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Cannot connect to the BuildPro server.';
      default:
        return 'The held carts could not be loaded. Try again.';
    }
  }
}
