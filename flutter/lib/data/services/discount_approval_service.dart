import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/json_field.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:dio/dio.dart';

/// What a manager's approval hands back: a one-time token, bound to the percent
/// they signed off (Phase 4 F4, decision 18).
class DiscountApproval {
  const DiscountApproval({
    required this.token,
    required this.percent,
    required this.approver,
    this.expiresAt,
  });

  factory DiscountApproval.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Missing required field "token"');
    }
    // The approver's name is display only, so an older body without it still
    // approves the discount; the token is the part the server checks.
    final approver = json['approver'];
    return DiscountApproval(
      token: token,
      percent: double.tryParse('${json['percent']}') ?? 0,
      approver: approver is String ? approver : '',
      expiresAt: nullableDateField(json, 'expires_at'),
    );
  }

  /// Opaque signed value, sent as `discount_approval` on THIS sale only.
  final String token;
  final double percent;

  /// The manager's display name, so the dialog can say who approved it.
  final String approver;
  final DateTime? expiresAt;
}

/// Raised when an approval cannot be obtained. [message] is safe to show a cashier.
class DiscountApprovalException implements Exception {
  const DiscountApprovalException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// `POST /api/v1/discount-approvals/` — a Store Manager or Admin signs off a
/// discount above the Admin's cap.
///
/// The password goes to the server and NOWHERE else: it is never stored, never
/// logged and never echoed back here. The response is a token that names the
/// approved percent, so it cannot be reused for a bigger discount, and the server
/// spends it on the first sale (a replay is refused).
class DiscountApprovalService {
  DiscountApprovalService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const approvalsPath = '/api/v1/discount-approvals/';

  Future<DiscountApproval> request({
    required String username,
    required String password,
    required double percent,
    required String reason,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        approvalsPath,
        data: {
          'username': username,
          // Sent as typed, in the request body only.
          'password': password,
          'percent': percent.toStringAsFixed(2),
          'reason': reason,
        },
      );
      final data = response.data;
      if (data == null) {
        throw const DiscountApprovalException(
          'The server did not return an approval. Ask the manager to try again.',
        );
      }
      return DiscountApproval.fromJson(data);
    } on DioException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const DiscountApprovalException(
        'The server returned an approval this app cannot read.',
      );
    }
  }

  DiscountApprovalException _failureFor(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final code = body['code'];
      final mapped = discountRefusalSentence(code is String ? code : null);
      if (mapped != null) {
        return DiscountApprovalException(mapped, code: code as String?);
      }
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) {
        return DiscountApprovalException(
          detail,
          code: code is String ? code : null,
        );
      }
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return const DiscountApprovalException(
          'Cannot connect to the BuildPro server. Ask the manager to try again.',
        );
      default:
        return const DiscountApprovalException(
          'The discount could not be approved. Ask the manager to try again.',
        );
    }
  }
}
