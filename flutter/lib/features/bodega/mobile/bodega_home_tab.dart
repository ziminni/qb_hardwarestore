import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/features/bodega/mobile/bodega_arrivals_tab.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_shell.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_widgets.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Height of one waiting-for-pick-up row; the box shows three, then scrolls.
const pickupRowHeight = 68.0;
const visiblePickupRows = 3;

/// Home: two counts, then the receipts waiting at the gate (three in view,
/// the rest a scroll away), then the arrivals waiting for the check.
class BodegaHomeTab extends StatelessWidget {
  const BodegaHomeTab({
    super.key,
    required this.onOpenTab,
    required this.onRefresh,
    this.takePhoto,
  });

  final ValueChanged<BodegaTab> onOpenTab;
  final Future<void> Function() onRefresh;
  final PhotoTaker? takePhoto;

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<BodegaViewmodel>();
    // Newest sale first: the receipt just rung up is the one at the gate.
    final claims = sortedClaims(viewmodel.openClaims);
    final arrivals = viewmodel.pendingDeliveries;
    final rows = claims.length.clamp(1, visiblePickupRows);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey('bodega-home'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (viewmodel.loadError case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                error,
                style: const TextStyle(color: AppColors.errorText),
              ),
            ),
          if (viewmodel.usingOfflineSnapshot ||
              viewmodel.queuedReleaseCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: MobileCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      color: AppColors.warningText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        viewmodel.queuedReleaseCount > 0
                            ? 'Offline snapshot · '
                                  '${viewmodel.queuedReleaseCount} '
                                  'release${viewmodel.queuedReleaseCount == 1 ? '' : 's'} '
                                  'queued to sync'
                            : 'Offline snapshot — quantities may have changed '
                                  'at the counter',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (viewmodel.queuedReleaseCount > 0)
                      TextButton(
                        key: const ValueKey('bodega-sync-outbox'),
                        onPressed: onRefresh,
                        child: const Text('Sync now'),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _CountTile(
                    key: const ValueKey('tile-pickups'),
                    count: claims.length,
                    label: 'Waiting for\npick-up',
                    icon: Icons.local_shipping_outlined,
                    dark: true,
                    onTap: () => onOpenTab(BodegaTab.pickups),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CountTile(
                    key: const ValueKey('tile-arrivals'),
                    count: arrivals.length,
                    label: 'Arrivals\nto check',
                    icon: Icons.inventory_2_outlined,
                    onTap: () => onOpenTab(BodegaTab.arrivals),
                  ),
                ),
              ],
            ),
          ),
          // No "See all" (owner 2026-11-19): pending pick-ups open only by
          // scanning, so the box scrolls instead of leading anywhere.
          const SectionHeader(title: 'Waiting for pick-up'),
          MobileCard(
            child: SizedBox(
              key: const ValueKey('pickup-box'),
              height: rows * pickupRowHeight,
              child: claims.isEmpty
                  ? const Center(
                      child: EmptyNote('Nothing waiting at the gate.'),
                    )
                  : _ScrollingPickups(claims: claims),
            ),
          ),
          SectionHeader(
            title: 'New arrivals',
            onSeeAll: () => onOpenTab(BodegaTab.arrivals),
          ),
          if (arrivals.isEmpty)
            const MobileCard(child: EmptyNote('No new arrivals to check.'))
          else
            for (final delivery in arrivals)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ArrivalTile(delivery: delivery, takePhoto: takePhoto),
              ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    super.key,
    required this.count,
    required this.label,
    required this.icon,
    required this.onTap,
    this.dark = false,
  });

  final int count;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? AppColors.brandWhite : AppColors.brandBlack;
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: dark ? AppColors.brandBlack : AppColors.brandGoldLight,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: dark ? AppColors.brandGold : AppColors.brandBlack,
                ),
                const Spacer(),
                Text(
                  '$count',
                  style: TextStyle(
                    color: fg,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(color: fg, fontSize: 13.5, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickupRow extends StatelessWidget {
  const _PickupRow({required this.claim});
  final BodegaClaim claim;

  @override
  Widget build(BuildContext context) {
    final number = claim.orNumber.isNotEmpty
        ? claim.orNumber
        : claim.transactionNo;
    return SizedBox(
      height: pickupRowHeight - 1,
      child: ListTile(
        // Shown, not opened (owner 2026-11-19): a pending pick-up opens only
        // by scanning its QR or typing its OR number in the scanner.
        leading: const CircleAvatar(
          backgroundColor: AppColors.surfaceMuted,
          child: Icon(Icons.receipt_long_outlined, color: AppColors.brandBlack),
        ),
        title: Text(
          number,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${claim.customerName.isEmpty ? 'Walk-in' : claim.customerName}'
          ' · ${claim.lines.length} item${claim.lines.length == 1 ? '' : 's'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // The date on its own, short, so a long customer name never cuts it
        // off (seen on the checker's phone: "Walk-in Customer · 1 item · No…").
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (claim.soldAt case final soldAt?)
              Text(
                formatShortDate(soldAt),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The pick-up box's list with an always-visible scroll bar on the right: a
/// gold thumb on a light track, so the checker sees at a glance that more
/// receipts sit below the first three.
class _ScrollingPickups extends StatefulWidget {
  const _ScrollingPickups({required this.claims});
  final List<BodegaClaim> claims;

  @override
  State<_ScrollingPickups> createState() => _ScrollingPickupsState();
}

class _ScrollingPickupsState extends State<_ScrollingPickups> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrolls = widget.claims.length > visiblePickupRows;
    return RawScrollbar(
      controller: _scroll,
      thumbVisibility: scrolls,
      trackVisibility: scrolls,
      thickness: 6,
      radius: const Radius.circular(8),
      trackRadius: const Radius.circular(8),
      thumbColor: AppColors.brandGold,
      trackColor: AppColors.surfaceMuted,
      trackBorderColor: Colors.transparent,
      crossAxisMargin: 3,
      mainAxisMargin: 6,
      child: ListView.separated(
        key: const ValueKey('pickup-list'),
        controller: _scroll,
        // Room on the right so the bar never sits on a row's text.
        padding: EdgeInsets.only(right: scrolls ? 12 : 0),
        itemCount: widget.claims.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, i) => _PickupRow(claim: widget.claims[i]),
      ),
    );
  }
}
