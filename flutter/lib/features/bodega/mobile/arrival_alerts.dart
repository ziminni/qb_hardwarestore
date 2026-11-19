import 'package:client/data/models/bodega.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows one phone notification. An interface so tests count the alerts.
abstract class AlertSender {
  Future<void> send(String title, String body);
}

/// The phone's notification bar, through flutter_local_notifications. Asks for
/// permission once (Android 13+ and iPhone); a refusal only means no banner.
class LocalAlertSender implements AlertSender {
  LocalAlertSender();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 1;

  static const _channel = AndroidNotificationDetails(
    'bodega_arrivals',
    'New arrivals',
    channelDescription: 'Supplier deliveries waiting for the Bodega check.',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> send(String title, String body) async {
    // Phones only: the desktop Bodega pages have no alert to give.
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await _init();
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (error) {
      // A missing permission or plugin must never break the checker's screen.
      debugPrint('Arrival alert not shown: $error');
    }
  }
}

/// Remembers which arrivals this phone has already announced, so each new
/// delivery to check is announced exactly once, even across app restarts.
class ArrivalAlerts {
  ArrivalAlerts({AlertSender? sender}) : _sender = sender ?? LocalAlertSender();

  static const seenKey = 'bodega_announced_arrivals';
  final AlertSender _sender;

  /// Announces the [pending] deliveries not announced before; answers them.
  Future<List<BodegaDelivery>> announce(List<BodegaDelivery> pending) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList(seenKey) ?? const []).toSet();
    final fresh = [
      for (final delivery in pending)
        if (!seen.contains('${delivery.id}')) delivery,
    ];
    if (fresh.isEmpty) return fresh;
    // Only still-pending ids are kept, so the list never grows without bound.
    await prefs.setStringList(seenKey, [
      for (final delivery in pending) '${delivery.id}',
    ]);
    if (fresh.length == 1) {
      final delivery = fresh.single;
      await _sender.send(
        'New arrival to check',
        '${delivery.number}${delivery.supplierName.isEmpty ? '' : ' · ${delivery.supplierName}'}'
            ' · ${delivery.lines.length} item${delivery.lines.length == 1 ? '' : 's'}',
      );
    } else {
      await _sender.send(
        '${fresh.length} new arrivals to check',
        'Open Arrivals to check them into the Bodega.',
      );
    }
    return fresh;
  }
}
