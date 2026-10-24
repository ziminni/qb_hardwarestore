import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:flutter/material.dart';

/// Opens the read-only notifications sheet.
///
/// Task 0 of Phase 3: the sales, inventory and admin shells each carried their
/// own `OutlinedButton.icon(onPressed: () {}, ...)` labelled "Notifications" —
/// three buttons that looked live and opened nothing. This is the one control
/// they share.
Future<void> showNotificationsSheet(
  BuildContext context, {
  InventoryService? service,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => NotificationsSheet(service: service),
  );
}

/// "Notifications" for the shared shells. Reads nothing until it is pressed:
/// a shell that fetched on build would hit `/api/v1/alerts/` on every
/// dashboard render, for every role.
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key, this.service});

  /// Injected by tests so the sheet can be driven without a server.
  final InventoryService? service;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => showNotificationsSheet(context, service: service),
      icon: const Icon(Icons.notifications_none, size: 17),
      label: const Text('Notifications'),
    );
  }
}

/// Unresolved system alerts, read-only.
///
/// Contract: `GET /api/v1/alerts/` — readable by **every** authenticated user,
/// and read-only for every role (ENDPOINTS.md; decision 06 makes alerts
/// system-generated). Resolving one is `POST /alerts/{id}/resolve/`, which is
/// Phase 4, so nothing here writes: no resolve button, no form.
///
/// The alert source is reused, not re-implemented: [InventoryService.fetchAlerts]
/// and [SystemAlert] are the existing authority over alert state (decision 13).
class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key, this.service});

  /// Injected by tests so the load path can be driven without a server.
  final InventoryService? service;

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  late final InventoryService _service;

  List<SystemAlert> _alerts = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? InventoryService();
    _load();
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
      // sheet as an error the user can report and retry.
      if (!mounted) return;
      setState(() => _error = 'The alerts could not be read: ${error.message}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Notifications',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Unresolved system alerts.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ..._body(context, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, ThemeData theme) {
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
        Text(error, style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: _load, child: const Text('Retry')),
        ),
      ];
    }
    if (_alerts.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text('No unresolved alerts.'),
        ),
      ];
    }
    return [
      for (final alert in _alerts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_iconFor(alert.type), size: 20),
          title: Text(alert.type.displayName),
          subtitle: Text(alert.message),
          trailing: alert.createdAt == null
              ? null
              : Text(
                  _shortDate(alert.createdAt!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
    ];
  }

  static IconData _iconFor(SystemAlertType type) => switch (type) {
    SystemAlertType.lowStock => Icons.trending_down,
    SystemAlertType.outOfStock => Icons.remove_shopping_cart_outlined,
    SystemAlertType.expiring => Icons.event_busy_outlined,
    SystemAlertType.unknown => Icons.info_outline,
  };
}

String _shortDate(DateTime date) =>
    '${date.month}/${date.day}/${date.year}';
