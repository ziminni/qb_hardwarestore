import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

// The building blocks of Admin → Dashboard, built once and shared by all five
// tabs (owner design 2026-11-18): a tab host with its loading, error and
// refresh states, the card frame, the "Needs attention" list, breakdown bars,
// expandable item rows, the read-only banner and the two-column layout.

/// Widest the dashboard content grows; it stays centred beyond this.
const double dashboardMaxWidth = 1100;

const double _iconSquare = 32;
const double _barHeight = 6;

/// Colour of a status as (text, tint, bar).
(Color, Color, Color) _toneColors(StatusTone tone) => switch (tone) {
  StatusTone.success => (
    AppColors.successText,
    AppColors.successTint,
    AppColors.success,
  ),
  StatusTone.warning => (
    AppColors.warningText,
    AppColors.warningTint,
    AppColors.warning,
  ),
  StatusTone.error => (
    AppColors.errorText,
    AppColors.errorTint,
    AppColors.error,
  ),
  StatusTone.info || StatusTone.neutral => (
    AppColors.brandGoldText,
    AppColors.brandGoldLight.withValues(alpha: 0.35),
    AppColors.brandGold,
  ),
};

const _tabular = [FontFeature.tabularFigures()];

// ---------------------------------------------------------------------------
// Loading one tab
// ---------------------------------------------------------------------------

/// One tab's data: loaded the first time the tab opens, then kept while the
/// Admin switches tabs. Each tab has its own, so one slow source never blocks
/// the others.
class DashboardTabController<T> extends ChangeNotifier {
  DashboardTabController(this._read);

  final Future<T> Function() _read;

  T? data;
  String? error;
  bool loading = false;

  bool get started => loading || data != null || error != null;

  /// Loads on the first visit only; later visits reuse what is held.
  void ensureLoaded() {
    if (!started) load();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      data = await _read();
    } on Exception catch (failure) {
      // The services throw exceptions whose text is safe to show.
      error = failure.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// Shows a tab's placeholder blocks, its error or its content.
class DashboardTabHost<T> extends StatelessWidget {
  const DashboardTabHost({
    super.key,
    required this.controller,
    required this.builder,
  });

  final DashboardTabController<T> controller;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final data = controller.data;
      if (data != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.error != null) ...[
              _RefreshFailed(controller.error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            builder(context, data),
          ],
        );
      }
      if (controller.error != null) {
        return DashboardError(
          message: controller.error!,
          onRetry: controller.load,
        );
      }
      return const DashboardPlaceholder();
    },
  );
}

/// First load: grey blocks shaped like the page, four tiles then two tall
/// blocks. No spinner.
class DashboardPlaceholder extends StatelessWidget {
  const DashboardPlaceholder({super.key});

  static Widget _block(double height) => Container(
    height: height,
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadii.large),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('dashboard-placeholder'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MetricGrid(children: [for (var i = 0; i < 4; i++) _block(96)]),
      const SizedBox(height: AppSpacing.lg),
      DashboardColumns(main: [_block(320)], side: [_block(320)]),
    ],
  );
}

/// A tab that could not load: a centred message and a way to try again.
class DashboardError extends StatelessWidget {
  const DashboardError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

/// A refresh failed but older figures are still on screen.
class _RefreshFailed extends StatelessWidget {
  const _RefreshFailed(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(
        Icons.cloud_off_outlined,
        size: 18,
        color: AppColors.errorText,
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          'Could not refresh: $message Showing the last figures.',
          style: const TextStyle(color: AppColors.errorText, fontSize: 13),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

/// A main column and a side column; stacked, main first, on a narrow window.
class DashboardColumns extends StatelessWidget {
  const DashboardColumns({super.key, required this.main, required this.side});

  final List<Widget> main;
  final List<Widget> side;

  static Widget _stack(List<Widget> cards) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.lg),
        cards[i],
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth < 860
        ? _stack([...main, ...side])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _stack(main)),
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: 2, child: _stack(side)),
            ],
          ),
  );
}

/// Light gold strip for a tab the Admin only reads: who records this data.
class ReadOnlyBanner extends StatelessWidget {
  const ReadOnlyBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('read-only-banner'),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    decoration: BoxDecoration(
      color: AppColors.brandGoldLight.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(AppRadii.medium),
      border: Border.all(color: AppColors.brandGoldLight),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.visibility_outlined,
          size: 18,
          color: AppColors.brandGoldText,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.brandGoldText),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

/// The 32 px rounded icon square used by card headers and attention rows.
class _IconSquare extends StatelessWidget {
  const _IconSquare(this.icon, {this.tone = StatusTone.neutral});

  final IconData icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (ink, tint, _) = _toneColors(tone);
    return Container(
      width: _iconSquare,
      height: _iconSquare,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Icon(icon, size: 18, color: ink),
    );
  }
}

/// A dashboard card: icon square, bold title, optional grey subtitle and an
/// optional text-button action. A list card ([edgeToEdge]) puts a divider
/// under the header and runs its rows to the card's edges.
class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.edgeToEdge = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool edgeToEdge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          _IconSquare(icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
    return Material(
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (edgeToEdge) ...[
            const Divider(height: 1),
            child,
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// Rows with a divider between each, edge to edge.
class _DividedRows extends StatelessWidget {
  const _DividedRows(this.rows);
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const Divider(height: 1),
        rows[i],
      ],
    ],
  );
}

// ---------------------------------------------------------------------------
// Needs attention
// ---------------------------------------------------------------------------

enum AttentionLevel { urgent, warning }

/// One problem: what is wrong, why it matters and, when there is one, where
/// to fix it.
class AttentionItem {
  const AttentionItem({
    required this.level,
    required this.title,
    required this.why,
    this.onOpen,
  });

  final AttentionLevel level;
  final String title;
  final String why;
  final VoidCallback? onOpen;
}

/// The card every tab's main column starts with. Urgent rows first; nothing
/// wrong shows one green "All clear" row with [clearReason].
class AttentionCard extends StatelessWidget {
  const AttentionCard({
    super.key,
    required this.items,
    required this.clearReason,
  });

  final List<AttentionItem> items;
  final String clearReason;

  @override
  Widget build(BuildContext context) {
    final sorted = [
      ...items.where((item) => item.level == AttentionLevel.urgent),
      ...items.where((item) => item.level == AttentionLevel.warning),
    ];
    return DashboardCard(
      key: const ValueKey('needs-attention'),
      icon: Icons.flag_outlined,
      title: 'Needs attention',
      subtitle: sorted.isEmpty
          ? null
          : '${sorted.length} ${sorted.length == 1 ? 'item' : 'items'}',
      edgeToEdge: true,
      child: sorted.isEmpty
          ? _AttentionRow(
              icon: Icons.check_circle_outline,
              tone: StatusTone.success,
              title: 'All clear',
              why: clearReason,
            )
          : _DividedRows([
              for (final item in sorted)
                _AttentionRow(
                  icon: item.level == AttentionLevel.urgent
                      ? Icons.error_outline
                      : Icons.warning_amber_rounded,
                  tone: item.level == AttentionLevel.urgent
                      ? StatusTone.error
                      : StatusTone.warning,
                  title: item.title,
                  why: item.why,
                  onOpen: item.onOpen,
                ),
            ]),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.why,
    this.onOpen,
  });

  final IconData icon;
  final StatusTone tone;
  final String title;
  final String why;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _IconSquare(icon, tone: tone),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  why,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onOpen != null)
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Breakdown bars
// ---------------------------------------------------------------------------

/// One bar: [value] sizes it, [display] is what is printed.
class BreakdownEntry {
  const BreakdownEntry({
    required this.label,
    required this.value,
    required this.display,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final double value;
  final String display;
  final StatusTone tone;
}

/// Label left, bold value right, a 6 px bar below sized against the largest
/// row and coloured by its status.
class BreakdownBars extends StatelessWidget {
  const BreakdownBars({super.key, required this.entries, required this.empty});

  final List<BreakdownEntry> entries;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Text(
        empty,
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }
    final largest = entries
        .map((entry) => entry.value)
        .fold<double>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _BreakdownRow(
            entries[i],
            share: largest <= 0 ? 0 : (entries[i].value / largest).clamp(0, 1),
          ),
        ],
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow(this.entry, {required this.share});

  final BreakdownEntry entry;
  final double share;

  @override
  Widget build(BuildContext context) {
    final (_, _, bar) = _toneColors(entry.tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              entry.display,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontFeatures: _tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(_barHeight / 2),
          child: SizedBox(
            height: _barHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.surfaceMuted),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: share,
                  child: ColoredBox(
                    key: ValueKey('bar-${entry.label}'),
                    color: bar,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Label / value lines and expandable item rows
// ---------------------------------------------------------------------------

/// A plain label and value, for small fixed facts in a side card.
class FactLine extends StatelessWidget {
  const FactLine(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFeatures: _tabular,
          ),
        ),
      ],
    ),
  );
}

/// One row of an item list: title, a one-line status (red when [late]), a
/// chip on the right; tapping it shows [facts] as label/value pairs.
class DashboardItem {
  const DashboardItem({
    required this.title,
    required this.status,
    required this.chip,
    this.chipTone = StatusTone.neutral,
    this.late = false,
    this.facts = const [],
  });

  final String title;
  final String status;
  final String chip;
  final StatusTone chipTone;
  final bool late;
  final List<(String, String)> facts;
}

/// A list card of [DashboardItem]s.
class ItemListCard extends StatelessWidget {
  const ItemListCard({
    super.key,
    required this.icon,
    required this.title,
    required this.items,
    required this.empty,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<DashboardItem> items;
  final String empty;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => DashboardCard(
    icon: icon,
    title: title,
    subtitle: subtitle,
    actionLabel: actionLabel,
    onAction: onAction,
    edgeToEdge: true,
    child: items.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              empty,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          )
        : _DividedRows([for (final item in items) _ItemRow(item)]),
  );
}

class _ItemRow extends StatefulWidget {
  const _ItemRow(this.item);
  final DashboardItem item;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: item.facts.isEmpty
              ? null
              : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        item.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: item.late
                              ? AppColors.errorText
                              : AppColors.textSecondary,
                          fontWeight: item.late
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusBadge(label: item.chip, tone: item.chipTone),
                if (item.facts.isNotEmpty)
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (label, value) in item.facts)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        value,
                        style: const TextStyle(fontFeatures: _tabular),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab bar and stat tiles (owner screenshot 2026-11-18)
// ---------------------------------------------------------------------------

/// One tab: its icon and label.
class DashboardTabSpec<T> {
  const DashboardTabSpec(this.value, this.label, this.icon);
  final T value;
  final String label;
  final IconData icon;
}

/// Underlined tabs: icon and label, the open one bold with a gold bar under
/// it, all on one rule across the page. Scrolls sideways on a phone.
class DashboardTabBar<T> extends StatelessWidget {
  const DashboardTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<DashboardTabSpec<T>> tabs;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs)
            _DashboardTabButton(
              label: tab.label,
              icon: tab.icon,
              selected: tab.value == selected,
              onTap: () => onSelect(tab.value),
            ),
        ],
      ),
    ),
  );
}

class _DashboardTabButton extends StatelessWidget {
  const _DashboardTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xl),
          // The underline is as wide as the icon and label above it.
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20, color: color),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          color: color,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // The open tab's underline; the same height on every tab so the
                // labels do not jump.
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.brandGold : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A stat tile: label with an icon square top-right, a large number, an
/// optional bar ([share] of 0–1), a caption and, when it opens somewhere, an
/// arrow. [tone] colours the number for figures that need a look.
class DashboardStat extends StatelessWidget {
  const DashboardStat({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    this.caption,
    this.share,
    this.tone = StatusTone.neutral,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final String value;
  final String? caption;
  final double? share;
  final StatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (ink, _, _) = _toneColors(tone);
    final valueColor = tone == StatusTone.neutral ? AppColors.textPrimary : ink;
    return Material(
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  _IconSquare(icon, tone: tone),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                  fontFeatures: _tabular,
                ),
              ),
              if (share != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                  child: LinearProgressIndicator(
                    value: share!.clamp(0, 1),
                    minHeight: _barHeight,
                    color: AppColors.brandGold,
                    backgroundColor: AppColors.surfaceMuted,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      caption ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
