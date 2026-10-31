import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/audit_log.dart';
import 'package:client/features/admin/widgets/admin_audit_action.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// The audit trail as one list: a table on a wide panel, cards on a narrow one.
///
/// Replaces the hand-built `DataTable` this screen used to scroll sideways,
/// which showed the server's raw action codes (`STOCK_ADJUST`) and a
/// hand-formatted `10/22/2026 14:05` timestamp. The panel brings the empty,
/// loading and error states too, so the page only decides which one applies.
///
/// Presentation only: the page filters and pages, and hands over the rows it
/// wants shown.
class AdminAuditLogTable extends StatelessWidget {
  const AdminAuditLogTable({
    super.key,
    required this.logs,
    required this.emptyMessage,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.onRowTap,
  });

  final List<AuditLog> logs;

  /// Worded by the page: "nothing recorded yet" and "nothing matches this
  /// filter" are different facts, and in an audit trail the difference matters.
  final String emptyMessage;

  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  /// Opens one entry. The Details column shortens a long sentence, and an audit
  /// trail whose sentence cannot be read in full hides a fact.
  final ValueChanged<AuditLog>? onRowTap;

  @override
  Widget build(BuildContext context) {
    return DataPanel<AuditLog>(
      columns: [
        // When and Action take two shares each: the timestamp is the reader's
        // first handle on a row, and "Stock adjustment" is the longest action
        // word, so one share wrapped it into three broken lines at 1100 px.
        // User takes three, because a full staff email is long; Details takes
        // four, because it is the sentence that explains the action.
        DataPanelColumn<AuditLog>(
          label: 'When',
          flex: 2,
          cell: (log) => Text(
            formatDateTime(log.timestamp.toLocal()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
        DataPanelColumn<AuditLog>(
          label: 'User',
          flex: 3,
          cell: (log) => Text(
            log.userEmail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
        DataPanelColumn<AuditLog>(
          label: 'Action',
          flex: 2,
          cell: (log) => StatusBadge(
            label: AdminAuditAction.label(log.actionType),
            tone: AdminAuditAction.tone(log.actionType),
          ),
        ),
        DataPanelColumn<AuditLog>(
          label: 'Details',
          flex: 4,
          cell: (log) => Text(
            log.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
      rows: logs,
      emptyMessage: emptyMessage,
      isLoading: isLoading,
      error: error,
      onRetry: onRetry,
      onRowTap: onRowTap,
      rowKey: (log) => ValueKey('AdminAuditLogTable.row.${log.id}'),
    );
  }
}
