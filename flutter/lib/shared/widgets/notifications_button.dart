import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Filter tabs shown inside the Notifications modal pop-up.
enum NotificationReadFilter {
  all('All'),
  unread('Unread'),
  read('Read');

  const NotificationReadFilter(this.label);
  final String label;
}

/// Opens the Notifications modal pop-up (`AppDialog`) with All / Unread / Read
/// filtering.
///
/// Task 0 of Phase 3: the sales, inventory and admin shells each carried their
/// own `OutlinedButton.icon(onPressed: () {}, ...)` labelled "Notifications" —
/// three buttons that looked live and opened nothing. This is the one control
/// they share.
Future<void> showNotificationsSheet(
  BuildContext context, {
  InventoryService? service,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog(
      icon: Icons.notifications_none_rounded,
      title: 'Notifications',
      subtitle: 'Unresolved system alerts.',
      width: 580,
      content: NotificationsSheet(service: service, embeddedInDialog: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// "Notifications" for the shared shells. Reads nothing until it is pressed:
/// a shell that fetched on build would hit `/api/v1/alerts/` on every
/// dashboard render, for every role.
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key, this.service});

  /// Injected by tests so the modal can be driven without a server.
  final InventoryService? service;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return OutlinedButton.icon(
      onPressed: () => showNotificationsSheet(context, service: service),
      style: OutlinedButton.styleFrom(
        backgroundColor: p.cardBackground,
        foregroundColor: p.textPrimary,
        side: BorderSide(color: p.border),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        textStyle: AppTextStyles.labelMedium.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: Icon(
        Icons.notifications_none_rounded,
        size: 16,
        color: p.accentInk,
      ),
      label: const Text('Notifications'),
    );
  }
}

/// Unresolved system alerts with local-device read/unread filtering.
///
/// Contract: `GET /api/v1/alerts/` — readable by **every** authenticated user,
/// and read-only for every role (ENDPOINTS.md; decision 06 makes alerts
/// system-generated). Nothing here writes to the server; read/unread state is
/// tracked locally per device via [SharedPreferences].
class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({
    super.key,
    this.service,
    this.embeddedInDialog = false,
  });

  /// Injected by tests so the load path can be driven without a server.
  final InventoryService? service;

  /// True when hosted inside [showNotificationsSheet]'s [AppDialog] chrome,
  /// avoiding duplicate title/subtitle headers.
  final bool embeddedInDialog;

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  static const String _readIdsKey = 'notifications_read_ids';

  late final InventoryService _service;

  List<SystemAlert> _alerts = const [];
  Set<int> _readIds = {};
  NotificationReadFilter _filter = NotificationReadFilter.all;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? InventoryService();
    _restoreReadIds();
    _load();
  }

  Future<void> _restoreReadIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_readIdsKey);
      if (!mounted || stored == null) return;
      setState(() {
        _readIds = {for (final raw in stored) ?int.tryParse(raw)};
      });
    } catch (_) {
      // Missing/unreadable local preferences must not break the feed.
    }
  }

  Future<void> _persistReadIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_readIdsKey, [
        for (final id in _readIds) '$id',
      ]);
    } catch (_) {
      // Keep the in-memory read state for this session even if storage fails.
    }
  }

  void _toggleRead(int alertId) {
    setState(() {
      if (_readIds.contains(alertId)) {
        _readIds.remove(alertId);
      } else {
        _readIds.add(alertId);
      }
    });
    _persistReadIds();
  }

  void _markAllRead() {
    setState(() {
      _readIds = {..._readIds, for (final alert in _alerts) alert.id};
    });
    _persistReadIds();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final alerts = await _service.fetchAlerts();
      if (!mounted) return;
      setState(() {
        // Resolved alerts are history, not a notification. The server row is
        // the authority on which is which — the client invents nothing.
        _alerts = alerts.where((alert) => !alert.isResolved).toList();
        _error = null;
      });
    } on InventoryServiceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on FormatException catch (error) {
      // A malformed alert row is a contract break, not a crash: it reaches the
      // modal as an error the user can report and retry.
      if (!mounted) return;
      setState(() => _error = 'The alerts could not be read: ${error.message}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<SystemAlert> get _visibleAlerts => switch (_filter) {
    NotificationReadFilter.all => _alerts,
    NotificationReadFilter.unread =>
      _alerts.where((a) => !_readIds.contains(a.id)).toList(),
    NotificationReadFilter.read =>
      _alerts.where((a) => _readIds.contains(a.id)).toList(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    final unreadCount = _alerts.where((a) => !_readIds.contains(a.id)).length;
    final readCount = _alerts.length - unreadCount;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.embeddedInDialog) ...[
          Text(
            'Notifications',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Unresolved system alerts.',
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterTabChip(
                  key: const ValueKey('notifications-filter-all'),
                  label: 'All',
                  count: _alerts.length,
                  selected: _filter == NotificationReadFilter.all,
                  onTap: () =>
                      setState(() => _filter = NotificationReadFilter.all),
                ),
                _FilterTabChip(
                  key: const ValueKey('notifications-filter-unread'),
                  label: 'Unread',
                  count: unreadCount,
                  selected: _filter == NotificationReadFilter.unread,
                  onTap: () =>
                      setState(() => _filter = NotificationReadFilter.unread),
                ),
                _FilterTabChip(
                  key: const ValueKey('notifications-filter-read'),
                  label: 'Read',
                  count: readCount,
                  selected: _filter == NotificationReadFilter.read,
                  onTap: () =>
                      setState(() => _filter = NotificationReadFilter.read),
                ),
              ],
            ),
            if (!_isLoading && _error == null && unreadCount > 0)
              TextButton.icon(
                key: const ValueKey('notifications-mark-all-read'),
                onPressed: _markAllRead,
                style: TextButton.styleFrom(
                  foregroundColor: p.accentInk,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text('Mark all read'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ..._body(context, theme),
      ],
    );

    if (widget.embeddedInDialog) return body;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: body,
      ),
    );
  }

  List<Widget> _body(BuildContext context, ThemeData theme) {
    final p = AppPalette.of(context);
    if (_isLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final error = _error;
    if (error != null) {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.isDark
                ? AppColors.error.withValues(alpha: 0.14)
                : AppColors.errorTint,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error,
                style: TextStyle(
                  color: p.isDark
                      ? const Color(0xFFFCA5A5)
                      : AppColors.errorText,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      ];
    }
    if (_alerts.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          decoration: BoxDecoration(
            color: p.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(color: p.border),
          ),
          child: Column(
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 28,
                color: p.textSecondary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No unresolved alerts.',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    final visible = _visibleAlerts;
    if (visible.isEmpty) {
      final emptyCopy = _filter == NotificationReadFilter.unread
          ? 'You are all caught up — no unread notifications.'
          : 'No read notifications yet.';
      return [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          decoration: BoxDecoration(
            color: p.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(color: p.border),
          ),
          child: Text(
            emptyCopy,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.textSecondary),
          ),
        ),
      ];
    }

    return [
      for (var i = 0; i < visible.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.sm),
        _NotificationRow(
          alert: visible[i],
          isRead: _readIds.contains(visible[i].id),
          onToggleRead: () => _toggleRead(visible[i].id),
        ),
      ],
    ];
  }
}

class _FilterTabChip extends StatelessWidget {
  const _FilterTabChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: selected ? p.selected : p.surfaceSunken,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: selected ? p.accent : p.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? p.accentInk : p.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? p.accent.withValues(alpha: 0.2)
                      : p.cardBackground,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? p.accentInk : p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.alert,
    required this.isRead,
    required this.onToggleRead,
  });

  final SystemAlert alert;
  final bool isRead;
  final VoidCallback onToggleRead;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final (Color badgeBg, Color badgeFg, IconData icon) = switch (alert.type) {
      SystemAlertType.outOfStock => (
        p.isDark
            ? AppColors.error.withValues(alpha: 0.18)
            : AppColors.errorTint,
        p.isDark ? const Color(0xFFFCA5A5) : AppColors.errorText,
        Icons.remove_shopping_cart_outlined,
      ),
      SystemAlertType.lowStock => (
        p.isDark
            ? AppColors.warning.withValues(alpha: 0.18)
            : AppColors.warningTint,
        p.isDark ? const Color(0xFFFCD34D) : AppColors.warningText,
        Icons.trending_down,
      ),
      SystemAlertType.expiring => (
        p.isDark
            ? AppColors.warning.withValues(alpha: 0.18)
            : AppColors.warningTint,
        p.isDark ? const Color(0xFFFCD34D) : AppColors.warningText,
        Icons.event_busy_outlined,
      ),
      SystemAlertType.unknown => (
        p.surfaceSunken,
        p.textSecondary,
        Icons.info_outline,
      ),
    };

    return Material(
      color: isRead ? p.surfaceSunken : p.selected.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: InkWell(
        key: ValueKey('notification-item-${alert.id}'),
        onTap: onToggleRead,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: isRead ? p.border : p.accent.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isRead ? Colors.transparent : p.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: Icon(icon, size: 18, color: badgeFg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.type.displayName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isRead
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (alert.createdAt != null)
                          Text(
                            _shortDate(alert.createdAt!),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: p.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.message,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: isRead ? 'Mark as unread' : 'Mark as read',
                onPressed: onToggleRead,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isRead
                      ? Icons.mark_email_unread_outlined
                      : Icons.mark_email_read_outlined,
                  size: 17,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _shortDate(DateTime date) => '${date.month}/${date.day}/${date.year}';
