import 'package:flutter/foundation.dart';

/// Lightweight in-app sync signal so mutations (accepting/declining a project
/// request, releasing materials, approving a receipt) immediately refresh
/// sidebar badges and active queues instead of waiting for the next poll tick.
class AppSyncBus extends ChangeNotifier {
  AppSyncBus._();

  static final AppSyncBus instance = AppSyncBus._();

  void notifyMarkersChanged() => notifyListeners();
}
