import 'package:client/core/network/paged.dart';
import 'package:client/data/models/audit_log.dart';
import 'package:client/data/services/audit_log_service.dart';

/// Policy-free pass-through over [AuditLogService], preserving the one data
/// path `View → ViewModel → Repository → Service → ApiClient`.
///
/// No caching, no filtering, no retry policy: D-01 locked the scope to "page 1,
/// latest first, load on open", and a repository that decided otherwise would be
/// a second, silent policy.
class AuditLogRepository {
  AuditLogRepository({AuditLogService? service})
    : _service = service ?? AuditLogService();

  final AuditLogService _service;

  Future<Paged<AuditLog>> fetchAuditLogs({int page = 1}) =>
      _service.fetchAuditLogs(page: page);
}
