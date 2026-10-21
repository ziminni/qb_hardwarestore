import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/paged.dart';
import 'package:client/data/models/audit_log.dart';
import 'package:dio/dio.dart';

/// Raised when the audit trail cannot be read. [message] is safe to show.
class AuditLogServiceException implements Exception {
  const AuditLogServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the admin-only audit trail (decision D-01).
///
/// `AuditLogViewSet` is `ReadOnlyModelViewSet` + `IsAdminUser`, ordered
/// `-timestamp` server-side, and paginated by DRF's `PAGE_SIZE` (50). So the
/// newest actions are on page 1 — which is why the screen loads page 1 only and
/// this service returns the [Paged] envelope instead of flattening it: the
/// caller may need `total`/`hasMore` later, and flattening one page into a list
/// would make "50 of 137" indistinguishable from "all 50".
class AuditLogService {
  AuditLogService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const auditLogsPath = '/api/v1/audit-logs/';

  /// One page of audit rows, newest first.
  Future<Paged<AuditLog>> fetchAuditLogs({int page = 1}) async {
    try {
      return await _client.getList<AuditLog>(
        auditLogsPath,
        AuditLog.fromJson,
        queryParameters: {'page': page},
      );
    } on DioException catch (error) {
      throw AuditLogServiceException(_message(error));
    } on FormatException catch (error) {
      // A malformed row is a contract break, not a network problem — but it
      // must still reach the screen as a retryable message rather than a raw
      // crash that blanks the table with no explanation.
      throw AuditLogServiceException(
        'The audit trail could not be read: ${error.message}',
      );
    }
  }

  String _message(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    if (error.response?.statusCode == 401) {
      return 'Your session has expired. Sign in again.';
    }
    if (error.response?.statusCode == 403) {
      return 'No permission to view the audit trail.';
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) return detail;
    }
    return 'The audit trail could not be loaded.';
  }
}
