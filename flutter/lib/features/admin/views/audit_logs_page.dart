import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/audit_log.dart';
import 'package:client/data/repositories/audit_log_repository.dart';
import 'package:client/data/services/audit_log_service.dart';
import 'package:client/features/admin/widgets/admin_audit_action.dart';
import 'package:client/features/admin/widgets/admin_audit_log_table.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';

/// The admin Audit Logs screen (decision D-01, refreshed by card A6).
///
/// Reads `GET /api/v1/audit-logs/`: admin-only, ordered `-timestamp`
/// server-side, paginated at DRF's 50. Page 1 is therefore the newest 50
/// actions, and the pager at the foot of the list walks back through the trail.
///
/// Search and the action chips filter the page on screen, not the archive: the
/// endpoint takes no filter parameters (D19, no new endpoints), so the caption
/// under the bar says exactly that instead of letting a narrowed list look like
/// the whole history.
///
/// State is page-local rather than a viewmodel because there is nothing to
/// share: one fetch, one page number, one list. A viewmodel here would be a
/// second place to look for the same fields, and the map's invariant is one data
/// path, which `View -> Repository -> Service -> ApiClient` already satisfies.
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

  /// The chip that filters nothing.
  static const String _anyAction = 'All';

  /// Says out loud that a filter is a client filter, not a fresh fetch.
  static const String _filterCaption =
      'Filters search the actions on this page only.';

  int _page = 1;
  bool _isLoading = true;
  bool _hasMore = false;
  String? _error;
  List<AuditLog> _logs = const [];

  String _query = '';
  String _action = _anyAction;

  /// True once the reader has narrowed the list, which changes what "nothing to
  /// show" means: an empty trail and an empty filter are different facts.
  bool get _filtered => _query.trim().isNotEmpty || _action != _anyAction;

  List<AuditLog> get _visible => [
    for (final log in _logs)
      if (_matches(log)) log,
  ];

  bool _matches(AuditLog log) {
    final label = AdminAuditAction.label(log.actionType);
    if (_action != _anyAction && label != _action) return false;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${log.userEmail} ${log.description} $label'.toLowerCase().contains(
      query,
    );
  }

  /// The action chips, in the order the actions appear on this page. A chip for
  /// an action nobody performed on this page would only be able to empty the
  /// list, and would read as "there were none" when the truth is "not here".
  List<String> get _actionChips {
    final labels = <String>[];
    for (final log in _logs) {
      final label = AdminAuditAction.label(log.actionType);
      if (!labels.contains(label)) labels.add(label);
    }
    return [_anyAction, ...labels];
  }

  @override
  void initState() {
    super.initState();
    // Post-frame, so the first frame paints the spinner and `setState` is never
    // called during `initState`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(1);
    });
  }

  /// Reads page [page] and, only on success, becomes that page.
  Future<void> _load(int page) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _repository.fetchAuditLogs(page: page);
      if (!mounted) return;
      setState(() {
        _logs = result.items;
        _page = page;
        _hasMore = result.hasMore;
      });
    } on AuditLogServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        // The rows on screen are still the page the reader is on: a failed
        // attempt at another page leaves them, and their page number, alone.
        // Only a failed FIRST page leaves nothing, and then the table shows the
        // failure instead of an empty trail.
        if (_logs.isEmpty) _hasMore = false;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final failure = _error;
    final hasRows = _logs.isNotEmpty;

    return AdminSkeletonLayout(
      title: 'Audit Logs',
      subtitle: 'Review recorded activity across the system.',
      selectedNavigationIndex: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterBar(
            searchHint: 'User, action, or details',
            onSearchChanged: (value) => setState(() => _query = value),
            options: _actionChips,
            selected: _action,
            onSelected: (chip) => setState(() => _action = chip),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            _filterCaption,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          // A refresh that failed under rows already read: the banner says so
          // above them, because the rows themselves are still true.
          if (failure != null && hasRows) ...[
            ErrorBanner(message: failure, onRetry: () => _load(_page)),
            const SizedBox(height: AppSpacing.md),
          ],
          AdminAuditLogTable(
            logs: rows,
            emptyMessage: _filtered
                ? 'No audit logs match these filters.'
                : 'No audit logs recorded.',
            // Only the first read may replace the list with a spinner, and only
            // while there is nothing to show yet.
            isLoading: _isLoading && !hasRows,
            error: hasRows ? null : failure,
            onRetry: () => _load(_page),
            onRowTap: _showEntry,
          ),
          if (hasRows) ...[const SizedBox(height: AppSpacing.md), _pager()],
        ],
      ),
    );
  }

  /// The whole entry, because the Details column shortens a long sentence and
  /// the IP address has no column at all. Read-only, like the trail itself.
  Future<void> _showEntry(AuditLog log) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AppPanel(
            title: 'Audit entry',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EntryField(
                  label: 'When',
                  value: formatDateTime(log.timestamp.toLocal()),
                ),
                _EntryField(label: 'User', value: log.userEmail),
                _EntryField(
                  label: 'Action',
                  value: AdminAuditAction.label(log.actionType),
                ),
                _EntryField(label: 'Details', value: log.description),
                // D18: a missing value says why it is missing.
                _EntryField(
                  label: 'IP address',
                  value: log.ipAddress ?? 'Not recorded',
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Walks the server pages: the newest actions are page 1, so "Next" reads
  /// older ones.
  Widget _pager() {
    return Row(
      children: [
        Text(
          'Page $_page',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: _isLoading || _page <= 1 ? null : () => _load(_page - 1),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Previous'),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          onPressed: _isLoading || !_hasMore ? null : () => _load(_page + 1),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Next'),
        ),
      ],
    );
  }
}

/// One labelled fact inside the entry dialog. The value wraps: a description is
/// the one field that may be a full sentence long.
class _EntryField extends StatelessWidget {
  const _EntryField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
