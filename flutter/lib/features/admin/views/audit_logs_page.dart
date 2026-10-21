import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/audit_log.dart';
import 'package:client/data/repositories/audit_log_repository.dart';
import 'package:client/data/services/audit_log_service.dart';
import 'package:client/features/admin/widgets/admin_audit_log_table.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';

/// The admin Audit Logs screen (decision D-01).
///
/// Replaces `AdminMockData.auditLogs` — three invented rows in the one screen
/// whose whole purpose is trustworthiness — with `GET /api/v1/audit-logs/`:
/// admin-only, ordered `-timestamp` server-side, paginated at DRF's 50. Page 1
/// is therefore the newest 50 actions, which is all this screen shows; there is
/// no filter and no paging control because D-01 scoped the view to exactly that.
///
/// State is page-local rather than a viewmodel because there is nothing to
/// share: one fetch, one list, one retry. A viewmodel here would be a second
/// place to look for the same three fields, and the map's invariant is one data
/// path — which `View → Repository → Service → ApiClient` already satisfies.
class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({super.key, this.repository});

  /// Injected by tests so loading, error and loaded states render without a
  /// server. Production builds its own.
  final AuditLogRepository? repository;

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  late final AuditLogRepository _repository =
      widget.repository ?? AuditLogRepository();

  bool _isLoading = true;
  String? _error;
  List<AuditLog> _logs = const [];

  @override
  void initState() {
    super.initState();
    // Post-frame, so the first frame paints the spinner and `setState` is never
    // called during `initState`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await _repository.fetchAuditLogs(page: 1);
      if (!mounted) return;
      setState(() => _logs = page.items);
    } on AuditLogServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        // A failed load must not leave the previous rows on screen under an
        // error banner: they would read as this load's result. An empty audit
        // table is also unacceptable, hence the banner replaces the table.
        _logs = const [];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// `M/D/YYYY H:MM` — month and day unpadded, minutes padded, hour unpadded.
  ///
  /// Deliberately not `intl`: this is the only formatted date on the screen and
  /// the audit table's TIME column is a plain string contract.
  String _formatTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    return '${local.month}/${local.day}/${local.year} '
        '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }

  /// Maps one [AuditLog] to a `AdminAuditLogTable` row.
  ///
  /// Contract locked by the widget: `[time, user, action, description]`.
  List<String> _row(AuditLog log) => [
    _formatTime(log.timestamp),
    log.userEmail,
    log.actionType,
    log.description,
  ];

  @override
  Widget build(BuildContext context) {
    return AdminSkeletonLayout(
      title: 'Audit Logs',
      subtitle: 'Review recorded activity across the system.',
      selectedNavigationIndex: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System activity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            LiveLoadErrorBanner(message: _error!, onRetry: _load)
          else if (_logs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('No audit logs recorded.')),
            )
          else
            AdminAuditLogTable(rows: _logs.map(_row).toList()),
        ],
      ),
    );
  }
}
