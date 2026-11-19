import 'dart:async';
import 'dart:io' show Platform;

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/bodega/mobile/arrival_alerts.dart';
import 'package:client/features/bodega/mobile/bodega_arrivals_tab.dart';
import 'package:client/features/bodega/mobile/bodega_home_tab.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_widgets.dart';
import 'package:client/features/bodega/mobile/bodega_notifications.dart';
import 'package:client/features/bodega/mobile/bodega_pickups_tab.dart';
import 'package:client/features/bodega/mobile/bodega_profile_tab.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:client/features/bodega/widgets/receipt_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// True in the Android and iPhone apps. `Platform` names the REAL device (a
/// widget test on a Mac answers false, whatever platform it pretends to be),
/// so the desktop and web Bodega pages are unchanged.
bool get runsAsPhoneApp => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// The tabs of the checker's phone app, in bottom-bar order. [scan] is an
/// action (it opens the camera), never a page of its own.
enum BodegaTab {
  home('Home', Icons.home_outlined, Icons.home),
  arrivals('Arrivals', Icons.inventory_2_outlined, Icons.inventory_2),
  scan('Scan', Icons.qr_code_scanner, Icons.qr_code_scanner),
  pickups('Pick-ups', Icons.local_shipping_outlined, Icons.local_shipping),
  profile('Profile', Icons.person_outline, Icons.person);

  const BodegaTab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The Bodega Checker's phone app (owner 2026-11-18): a brand header, the
/// page, and a bottom bar of Home, Arrivals, Scan, Pick-ups and Profile.
///
/// Arrivals are re-read every [pollEvery] and whenever the app comes back to
/// the front; a delivery not announced before raises a phone notification.
class BodegaMobileShell extends StatefulWidget {
  const BodegaMobileShell({
    super.key,
    this.viewmodel,
    this.scanner,
    this.takePhoto,
    this.alerts,
    this.pollEvery = const Duration(minutes: 1),
  });

  final BodegaViewmodel? viewmodel;

  /// Injected by tests; the phone uses the camera.
  final ReceiptScanner? scanner;
  final PhotoTaker? takePhoto;
  final ArrivalAlerts? alerts;
  final Duration pollEvery;

  @override
  State<BodegaMobileShell> createState() => _BodegaMobileShellState();
}

class _BodegaMobileShellState extends State<BodegaMobileShell>
    with WidgetsBindingObserver {
  late final BodegaViewmodel _viewmodel = widget.viewmodel ?? BodegaViewmodel();
  late final ArrivalAlerts _alerts = widget.alerts ?? ArrivalAlerts();
  BodegaTab _tab = BodegaTab.home;
  Timer? _poll;

  /// The notifications this phone has opened (see [NotificationReads]).
  Set<String> _read = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationReads.load().then((read) {
      if (mounted) setState(() => _read = read);
    });
    _refresh();
    _poll = Timer.periodic(widget.pollEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.viewmodel == null) _viewmodel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    await _viewmodel.loadHome();
    if (!mounted || _viewmodel.loadError != null) return;
    await _alerts.announce(_viewmodel.pendingDeliveries);
  }

  /// The bell: the notification sheet; a tapped notification opens its arrival.
  Future<void> _openNotifications() async {
    final picked = await showBodegaNotifications(
      context,
      deliveries: _viewmodel.deliveries,
      read: _read,
      onReadChanged: (read) {
        setState(() => _read = read);
        NotificationReads.save(read);
      },
    );
    if (picked == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<BodegaViewmodel>.value(
          value: _viewmodel,
          child: ArrivalReportScreen(
            deliveryId: picked.id,
            takePhoto: widget.takePhoto ?? takePhotoWithCamera,
          ),
        ),
      ),
    );
  }

  int get _unread => [
    for (final delivery in _viewmodel.deliveries)
      if (!_read.contains(notificationId(delivery))) delivery,
  ].length;

  void _select(BodegaTab tab) {
    if (tab == BodegaTab.scan) {
      scanAndOpenClaim(context, _viewmodel, widget.scanner);
      return;
    }
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BodegaViewmodel>.value(
      value: _viewmodel,
      child: Builder(
        builder: (context) {
          final viewmodel = context.watch<BodegaViewmodel>();
          final user = context.watch<AuthViewmodel>().user;
          // White status-bar icons over the black header, on every phone.
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: Column(
                children: [
                  BodegaHeader(
                    title: _tab == BodegaTab.home ? 'Bodega' : _tab.label,
                    name: user?.fullName ?? '',
                    arrivalsWaiting: _unread,
                    onBell: _openNotifications,
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _tab.index,
                      children: [
                        BodegaHomeTab(
                          onOpenTab: _select,
                          onRefresh: _refresh,
                          takePhoto: widget.takePhoto,
                        ),
                        BodegaArrivalsTab(
                          onRefresh: _refresh,
                          takePhoto: widget.takePhoto,
                        ),
                        const SizedBox.shrink(),
                        BodegaPickupsTab(
                          onRefresh: _refresh,
                          scanner: widget.scanner,
                        ),
                        BodegaProfileTab(takePhoto: widget.takePhoto),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: BodegaBottomBar(
                selected: _tab,
                arrivalsWaiting: viewmodel.pendingDeliveries.length,
                pickupsWaiting: viewmodel.openClaims.length,
                onSelect: _select,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The black brand bar: the Queen Builders logo (or a back arrow), the page's
/// name, and a bell with the unread count that opens the notifications.
class BodegaHeader extends StatelessWidget {
  const BodegaHeader({
    super.key,
    required this.title,
    required this.name,
    this.arrivalsWaiting = 0,
    this.onBell,
    this.onBack,
    this.subtitle,
  });

  final String title;
  final String name;
  final int arrivalsWaiting;

  /// The bell; hidden when null (a pushed page has no tabs to jump to).
  final VoidCallback? onBell;

  /// A back arrow in place of the QB mark, for pages opened from a tab.
  final VoidCallback? onBack;

  /// Replaces the "Queen Builders · name" line when given.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('bodega-header'),
      decoration: const BoxDecoration(
        color: AppColors.brandBlack,
        border: Border(
          bottom: BorderSide(color: AppColors.brandGold, width: 2),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
          child: Row(
            children: [
              if (onBack case final back?)
                IconButton(
                  key: const ValueKey('bodega-back'),
                  tooltip: 'Back',
                  onPressed: back,
                  icon: const Icon(
                    Icons.arrow_back,
                    color: AppColors.brandWhite,
                  ),
                )
              else
                // The Queen Builders logo (black and gold on white), on a white
                // tile so its black lines stay visible on the black bar.
                Container(
                  key: const ValueKey('bodega-logo'),
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.brandWhite,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Image.asset(AppAssets.logo, fit: BoxFit.contain),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.brandWhite,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // An empty subtitle means none: a pushed page shows only its title.
                    if (subtitle != '')
                      Text(
                        subtitle ??
                            (name.isEmpty
                                ? 'Queen Builders · Bodega Checker'
                                : 'Queen Builders · $name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.brandGoldLight,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
              if (onBell != null)
                IconButton(
                  key: const ValueKey('bodega-bell'),
                  tooltip: 'Arrivals to check',
                  onPressed: onBell,
                  icon: CountBadge(
                    count: arrivalsWaiting,
                    child: const Icon(
                      Icons.notifications_outlined,
                      color: AppColors.brandWhite,
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

/// The bottom bar: four tabs around a raised gold Scan button.
class BodegaBottomBar extends StatelessWidget {
  const BodegaBottomBar({
    super.key,
    required this.selected,
    required this.arrivalsWaiting,
    required this.pickupsWaiting,
    required this.onSelect,
  });

  final BodegaTab selected;
  final int arrivalsWaiting;
  final int pickupsWaiting;
  final ValueChanged<BodegaTab> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget item(BodegaTab tab, {int count = 0}) {
      final on = tab == selected;
      final colour = on ? AppColors.brandGoldText : AppColors.textSecondary;
      return Expanded(
        child: InkWell(
          key: ValueKey('bodega-tab-${tab.name}'),
          onTap: () => onSelect(tab),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CountBadge(
                  count: count,
                  child: Icon(on ? tab.selectedIcon : tab.icon, color: colour),
                ),
                const SizedBox(height: 3),
                Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colour,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: AppColors.brandWhite,
      elevation: 8,
      child: SafeArea(
        top: false,
        // Tall enough for the raised Scan circle and its label; the four tabs
        // sit on the bottom edge beside it.
        child: SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              item(BodegaTab.home),
              item(BodegaTab.arrivals, count: arrivalsWaiting),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('bodega-tab-scan'),
                  onTap: () => onSelect(BodegaTab.scan),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: AppColors.brandGold,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.brandWhite,
                            width: 3,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner,
                          color: AppColors.brandBlack,
                          size: 28,
                        ),
                      ),
                      const Text(
                        'Scan',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandBlack,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
              item(BodegaTab.pickups, count: pickupsWaiting),
              item(BodegaTab.profile),
            ],
          ),
        ),
      ),
    );
  }
}
