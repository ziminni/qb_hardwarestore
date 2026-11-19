import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/bodega.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which notifications this phone has opened. Kept on the phone: reading one
/// is a person's own state, not the server's.
class NotificationReads {
  static const key = 'bodega_read_notifications';

  static Future<Set<String>> load() async =>
      ((await SharedPreferences.getInstance()).getStringList(key) ?? const [])
          .toSet();

  static Future<void> save(Set<String> ids) async =>
      (await SharedPreferences.getInstance()).setStringList(key, ids.toList());
}

/// The id a delivery's notification is stored under.
String notificationId(BodegaDelivery delivery) => 'delivery-${delivery.id}';

enum NotificationFilter { all, unread, read }

/// The bell's sheet: every arrival as a notification, newest first, with
/// All / Unread / Read and "Mark all as read". Tapping one answers it.
Future<BodegaDelivery?> showBodegaNotifications(
  BuildContext context, {
  required List<BodegaDelivery> deliveries,
  required Set<String> read,
  required ValueChanged<Set<String>> onReadChanged,
}) {
  return showModalBottomSheet<BodegaDelivery>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NotificationSheet(
      deliveries: deliveries,
      read: read,
      onReadChanged: onReadChanged,
    ),
  );
}

class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet({
    required this.deliveries,
    required this.read,
    required this.onReadChanged,
  });

  final List<BodegaDelivery> deliveries;
  final Set<String> read;
  final ValueChanged<Set<String>> onReadChanged;

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  late final Set<String> _read = {...widget.read};
  NotificationFilter _filter = NotificationFilter.all;

  List<BodegaDelivery> get _sorted => [...widget.deliveries]
    ..sort((a, b) {
      final at = a.createdAt, bt = b.createdAt;
      if (at == null || bt == null) return b.id.compareTo(a.id);
      return bt.compareTo(at);
    });

  void _markAll() {
    setState(() => _read.addAll(widget.deliveries.map(notificationId)));
    widget.onReadChanged({..._read});
  }

  void _open(BodegaDelivery delivery) {
    _read.add(notificationId(delivery));
    widget.onReadChanged({..._read});
    Navigator.of(context).pop(delivery);
  }

  @override
  Widget build(BuildContext context) {
    final all = _sorted;
    final unread = all.where((d) => !_read.contains(notificationId(d))).length;
    final shown = [
      for (final delivery in all)
        if (switch (_filter) {
          NotificationFilter.all => true,
          NotificationFilter.unread => !_read.contains(
            notificationId(delivery),
          ),
          NotificationFilter.read => _read.contains(notificationId(delivery)),
        })
          delivery,
    ];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Notifications',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: unread == 0 ? null : _markAll,
                  child: const Text('Mark all as read'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<NotificationFilter>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: NotificationFilter.all,
                  label: Text('All (${all.length})'),
                ),
                ButtonSegment(
                  value: NotificationFilter.unread,
                  label: Text('Unread ($unread)'),
                ),
                ButtonSegment(
                  value: NotificationFilter.read,
                  label: Text('Read (${all.length - unread})'),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (picked) =>
                  setState(() => _filter = picked.single),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(switch (_filter) {
                      NotificationFilter.unread => 'You have read everything.',
                      NotificationFilter.read => 'Nothing read yet.',
                      NotificationFilter.all => 'No notifications yet.',
                    }, style: const TextStyle(color: AppColors.textSecondary)),
                  )
                : ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, i) {
                      final delivery = shown[i];
                      final isRead = _read.contains(notificationId(delivery));
                      final items = delivery.lines.length;
                      return ListTile(
                        onTap: () => _open(delivery),
                        tileColor: isRead ? null : AppColors.selected,
                        leading: CircleAvatar(
                          backgroundColor: delivery.isPending
                              ? AppColors.brandGold
                              : AppColors.successTint,
                          child: Icon(
                            delivery.isPending
                                ? Icons.inventory_2_outlined
                                : Icons.task_alt,
                            color: delivery.isPending
                                ? AppColors.brandBlack
                                : AppColors.successText,
                          ),
                        ),
                        title: Text(
                          delivery.isPending
                              ? 'New arrival to check'
                              : 'Arrival checked',
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          [
                            delivery.number,
                            if (delivery.supplierName.isNotEmpty)
                              delivery.supplierName,
                            '$items item${items == 1 ? '' : 's'}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (delivery.createdAt case final at?)
                              Text(
                                formatShortDate(at),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            if (!isRead)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
