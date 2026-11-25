import 'dart:math' as math;

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/services/admin_dashboard_service.dart';
import 'package:client/features/admin/widgets/dashboard_kit.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/analytics_charts.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/shared/widgets/stitch_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The tabs of Admin → Dashboard, in reading order (owner 2026-11-18).
enum AdminDashboardTab {
  system('System', Icons.settings_suggest_outlined),
  sales('Sales', Icons.point_of_sale_outlined),
  inventory('Inventory', Icons.inventory_2_outlined),
  bodega('Bodega', Icons.warehouse_outlined),
  finance('Finance', Icons.account_balance_outlined);

  const AdminDashboardTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Admin → Dashboard: the Admin's own overview of the whole shop.
///
/// Built here, not borrowed from the Sales or Stock dashboards. Each tab reads
/// its own section of `/reports/admin-dashboard/` the first time it opens and
/// keeps it while the Admin switches tabs; Refresh re-reads the open tab.
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key, this.service, this.initialTab});

  /// Injected by tests so the page renders without a server.
  final AdminDashboardService? service;
  final AdminDashboardTab? initialTab;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late final AdminDashboardService _service =
      widget.service ?? AdminDashboardService();
  late AdminDashboardTab _tab = widget.initialTab ?? AdminDashboardTab.system;
  late final Map<
    AdminDashboardTab,
    DashboardTabController<DashboardSectionRead>
  >
  _tabs = {
    for (final tab in AdminDashboardTab.values)
      tab: DashboardTabController(() => _service.fetchSection(tab.name)),
  };

  DashboardTabController<DashboardSectionRead> get _current => _tabs[_tab]!;

  @override
  void initState() {
    super.initState();
    _current.ensureLoaded();
  }

  @override
  void dispose() {
    for (final controller in _tabs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _select(AdminDashboardTab tab) {
    setState(() => _tab = tab);
    _current.ensureLoaded();
  }

  void _go(String route) => context.go(route);

  @override
  Widget build(BuildContext context) {
    return AdminSkeletonLayout(
      title: 'Dashboard',
      subtitle: 'The whole shop at a glance.',
      selectedNavigationIndex: AppDestinations.indexOf(
        'admin.overview',
        AppAreas.admin,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: dashboardMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: AppSpacing.lg),
              DashboardTabHost<DashboardSectionRead>(
                key: ValueKey('host-${_tab.name}'),
                controller: _current,
                builder: (context, read) => switch (_tab) {
                  AdminDashboardTab.system => _SystemTab(read.section, _go),
                  AdminDashboardTab.sales => _SalesTab(read.section),
                  AdminDashboardTab.inventory => _InventoryTab(read.section),
                  AdminDashboardTab.bodega => _BodegaTab(read.section),
                  AdminDashboardTab.finance => _FinanceTab(read.section),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => ListenableBuilder(
    listenable: _current,
    builder: (context, _) {
      final asOf = _current.data?.asOf;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardTabBar<AdminDashboardTab>(
            key: const ValueKey('admin-dashboard-tabs'),
            tabs: [
              for (final tab in AdminDashboardTab.values)
                DashboardTabSpec(tab, tab.label, tab.icon),
            ],
            selected: _tab,
            onSelect: _select,
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: StitchColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: StitchColors.cardBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const StitchPill(
                        label: 'Store & Bodega · Live',
                        tone: StitchTone.success,
                        icon: Icons.circle,
                      ),
                      if (asOf != null)
                        Text(
                          'Updated ${formatDateTime(asOf.toLocal())}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: StitchColors.inkMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  key: const ValueKey('dashboard-refresh'),
                  onPressed: _current.loading ? null : _current.load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StitchColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text(
                    'Refresh',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Small readers
// ---------------------------------------------------------------------------

typedef _Go = void Function(String route);

String _whole(DashboardSection s, String key) => formatPesoWhole(s.money(key));

String _count(DashboardSection s, String key) => formatCount(s.count(key));

double _num(Object? value) => double.tryParse('${value ?? ''}') ?? 0;

DateTime? _date(Object? value) => DateTime.tryParse('${value ?? ''}');

String _day(Object? value) {
  final date = _date(value);
  return date == null ? '' : formatDate(date.toLocal());
}

String _when(Object? value) {
  final date = _date(value);
  return date == null ? '' : formatDateTime(date.toLocal());
}

String _plural(int count, String one, [String? many]) =>
    '$count ${count == 1 ? one : (many ?? '${one}s')}';

Widget _tab(
  String key, {
  String? readOnly,
  required List<Widget> tiles,
  required List<Widget> main,
  required List<Widget> side,
}) => Column(
  key: ValueKey(key),
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    if (readOnly != null) ...[
      ReadOnlyBanner(readOnly),
      const SizedBox(height: AppSpacing.lg),
    ],
    MetricGrid(children: tiles),
    const SizedBox(height: AppSpacing.lg),
    DashboardColumns(main: main, side: side),
  ],
);

// ---------------------------------------------------------------------------
// The five tabs
// ---------------------------------------------------------------------------

class _SystemTab extends StatelessWidget {
  const _SystemTab(this.s, this.go);
  final DashboardSection s;
  final _Go go;

  static const _roleNames = {
    'admin': 'Admin',
    'sales': 'Store Manager',
    'inventory': 'Stock Manager',
    'pos': 'Cashier',
    'bodega': 'Bodega Checker',
  };

  @override
  Widget build(BuildContext context) {
    final roles = s.map('users_by_role');
    final failed = s.count('failed_logins_7d');
    final admins = (roles['admin'] as num?)?.toInt() ?? 0;
    final inactiveShelves = [
      for (final row in s.rows('locations'))
        if (row['is_active'] != true) '${row['name']}',
    ];
    return _tab(
      'tab-system',
      tiles: [
        StitchKpiCard(
          label: 'User accounts',
          subtitle: 'Active accounts',
          icon: Icons.group_outlined,
          value: _count(s, 'users_active'),
          tone: StitchTone.primary,
          progress: s.count('users_total') == 0
              ? 0
              : s.count('users_active') / s.count('users_total'),
          pillLabel: '${_count(s, 'users_inactive')} switched off',
          pillTone: s.count('users_inactive') > 0
              ? StitchTone.warning
              : StitchTone.neutral,
          onTap: () => go(AppRoutes.adminUserManagement),
        ),
        StitchKpiCard(
          label: 'Sign-ins today',
          icon: Icons.login,
          value: _count(s, 'logins_today'),
          tone: StitchTone.success,
          pillLabel: 'Today',
          pillTone: StitchTone.success,
        ),
        StitchKpiCard(
          label: 'Failed sign-ins',
          icon: Icons.no_accounts_outlined,
          value: _count(s, 'failed_logins_7d'),
          tone: failed > 0 ? StitchTone.danger : StitchTone.neutral,
          valueColor: failed > 0 ? StitchColors.danger : null,
          pillLabel: 'last 7 days',
          pillTone: failed > 0 ? StitchTone.danger : StitchTone.neutral,
          onTap: () => go(AppRoutes.adminAuditLogs),
        ),
        StitchKpiCard(
          label: 'Recorded actions today',
          icon: Icons.history,
          value: _count(s, 'events_today'),
          tone: StitchTone.primary,
          pillLabel: 'audit trail',
          pillTone: StitchTone.neutral,
          onTap: () => go(AppRoutes.adminAuditLogs),
        ),
      ],
      main: [
        AttentionCard(
          clearReason: 'No failed sign-ins this week and more than one Admin.',
          items: [
            if (admins <= 1)
              AttentionItem(
                level: AttentionLevel.urgent,
                title: admins == 0 ? 'No active Admin' : 'Only one Admin',
                why:
                    'If that account is locked out, nobody can manage users '
                    'or settings.',
                onOpen: () => go(AppRoutes.adminUserManagement),
              ),
            if (failed > 0)
              AttentionItem(
                level: failed >= 10
                    ? AttentionLevel.urgent
                    : AttentionLevel.warning,
                title: '${_plural(failed, 'failed sign-in')} this week',
                why:
                    'Check in the audit log that it was staff mistyping, '
                    'not someone guessing.',
                onOpen: () => go(AppRoutes.adminAuditLogs),
              ),
            for (final name in inactiveShelves)
              AttentionItem(
                level: AttentionLevel.warning,
                title: '$name is switched off',
                why: 'New stock cannot be put there until it is active again.',
                onOpen: () => go(AppRoutes.adminStorageLocations),
              ),
          ],
        ),
        ItemListCard(
          icon: Icons.history,
          title: 'Latest activity',
          subtitle: 'From the audit log',
          actionLabel: 'Audit logs',
          onAction: () => go(AppRoutes.adminAuditLogs),
          empty: 'Nothing recorded yet.',
          items: [
            for (final row in s.rows('recent_events'))
              DashboardItem(
                title: '${row['action']} · ${row['user']}',
                status: '${row['description']}',
                chip: _when(row['when']),
                facts: [
                  ('Who', '${row['user']}'),
                  ('What', '${row['action']}'),
                  ('When', _when(row['when'])),
                  ('Details', '${row['description']}'),
                ],
              ),
          ],
        ),
      ],
      side: [
        DashboardCard(
          icon: Icons.group_outlined,
          title: 'Accounts by role',
          subtitle: 'Active accounts only',
          actionLabel: 'Manage',
          onAction: () => go(AppRoutes.adminUserManagement),
          child: BreakdownBars(
            empty: 'No active accounts.',
            entries: [
              for (final entry in _roleNames.entries)
                BreakdownEntry(
                  label: entry.value,
                  value: ((roles[entry.key] as num?) ?? 0).toDouble(),
                  display: '${roles[entry.key] ?? 0}',
                  tone: entry.key == 'admin' && admins <= 1
                      ? StatusTone.error
                      : StatusTone.neutral,
                ),
            ],
          ),
        ),
        DashboardCard(
          icon: Icons.tune,
          title: 'Store setup',
          actionLabel: 'Settings',
          onAction: () => go(AppRoutes.adminSettings),
          child: Column(
            children: [
              FactLine(
                'VAT',
                s.flag('vat_registered')
                    ? 'Registered, ${s.text('vat_rate')}%'
                    : 'Not registered',
              ),
              FactLine(
                'Cashier discount cap',
                '${s.text('discount_cap_percent')}%',
              ),
              if (s.has('held_cart_expiry_minutes'))
                FactLine(
                  'Held cart expiry',
                  '${s.count('held_cart_expiry_minutes')} min',
                ),
              for (final row in s.rows('locations'))
                FactLine(
                  row['is_bodega'] == true
                      ? '${row['name']} (Bodega)'
                      : '${row['name']}',
                  row['is_active'] == true ? 'Active' : 'Switched off',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab(this.s);
  final DashboardSection s;

  @override
  Widget build(BuildContext context) {
    final stale = s.rows('stale_shifts');
    final returns = s.count('month_returns_count');
    final last7Days = s.rows('last_7_days');
    final peak7d = last7Days.fold<double>(
      0,
      (best, row) => math.max(best, _num(row['total'])),
    );
    final total7d = last7Days.fold<double>(
      0,
      (sum, row) => sum + _num(row['total']),
    );
    final monthGrossProfit = s.money('month_gross_profit');
    return _tab(
      'tab-sales',
      readOnly:
          'Cashiers record sales and returns at the till. This tab only '
          'shows them.',
      tiles: [
        StitchKpiCard(
          label: 'Sales today',
          icon: Icons.point_of_sale_outlined,
          value: _whole(s, 'today_total'),
          tone: StitchTone.primary,
          pillLabel: _plural(s.count('today_transactions'), 'transaction'),
          pillTone: StitchTone.primary,
        ),
        StitchKpiCard(
          label: 'Sales this month',
          icon: Icons.calendar_month_outlined,
          value: _whole(s, 'month_total'),
          tone: StitchTone.primary,
          pillLabel: _plural(s.count('month_transactions'), 'transaction'),
          pillTone: StitchTone.neutral,
        ),
        StitchKpiCard(
          label: 'Returns this month',
          icon: Icons.assignment_return_outlined,
          value: _whole(s, 'month_returns_total'),
          tone: returns > 0 ? StitchTone.warning : StitchTone.neutral,
          pillLabel: _plural(returns, 'return'),
          pillTone: returns > 0 ? StitchTone.warning : StitchTone.neutral,
        ),
        StitchKpiCard(
          label: 'Open shifts',
          icon: Icons.schedule,
          value: _count(s, 'open_shifts'),
          tone: stale.isNotEmpty ? StitchTone.danger : StitchTone.success,
          valueColor: stale.isNotEmpty ? StitchColors.danger : null,
          pillLabel: stale.isNotEmpty
              ? '${stale.length} stale'
              : 'On schedule',
          pillTone: stale.isNotEmpty ? StitchTone.danger : StitchTone.success,
        ),
        if (s.has('month_vat_total'))
          StitchKpiCard(
            label: 'VAT this month (All)',
            icon: Icons.receipt_long_outlined,
            value: _whole(s, 'month_vat_total'),
            tone: StitchTone.neutral,
            subtitle: 'OR-tagged only: ${_whole(s, 'month_or_vat')}',
            pillLabel: _plural(s.count('month_or_count'), 'OR'),
            pillTone: StitchTone.primary,
          ),
        if (s.has('month_gross_profit'))
          StitchKpiCard(
            label: 'Gross profit (month)',
            icon: Icons.trending_up,
            value: _whole(s, 'month_gross_profit'),
            tone: monthGrossProfit < 0
                ? StitchTone.danger
                : StitchTone.success,
            valueColor: monthGrossProfit < 0
                ? StitchColors.danger
                : StitchColors.successInk,
            pillLabel: s.has('month_margin_percent')
                ? '${s.text('month_margin_percent')}% margin'
                      '${s.flag('month_cost_coverage_complete') ? '' : ' (partial cost)'}'
                : 'Net sales ex-VAT minus COGS',
            pillTone: monthGrossProfit < 0
                ? StitchTone.danger
                : StitchTone.success,
          ),
      ],
      main: [
        AttentionCard(
          clearReason: 'Every shift from earlier days was closed out.',
          items: [
            for (final row in stale)
              AttentionItem(
                level: AttentionLevel.urgent,
                title: 'Shift left open since ${_day(row['opened_at'])}',
                why:
                    '${row['cashier']} never closed out, so that drawer\'s '
                    'cash was not counted.',
              ),
          ],
        ),
        if (last7Days.isNotEmpty) ...[
          GroupedBarTrendChart(
            key: const ValueKey('admin-dashboard-7d-chart'),
            title: 'Revenue, COGS & Gross Profit Trajectory (Last 7 Days)',
            subtitle:
                'Daily sales, landed COGS, and gross profit across the last 7 days.',
            primaryLabel: 'Sales',
            primaryColor: StitchColors.primaryDeep,
            secondaryLabel: 'COGS',
            secondaryColor: const Color(0xFF93C5FD),
            lineLabel: 'Profit',
            lineColor: StitchColors.success,
            height: 210,
            points: [
              for (final row in last7Days)
                TrendPoint(
                  label: _shortDay(row['date']),
                  primary: _num(row['total']),
                  secondary: row['cogs'] != null ? _num(row['cogs']) : null,
                  lineValue: row['gross_profit'] != null
                      ? _num(row['gross_profit'])
                      : null,
                ),
            ],
          ),
          _VelocitySummaryStrip(
            peak7d: formatPesoWhole(peak7d),
            total7d: formatPesoWhole(total7d),
            monthMargin: s.has('month_margin_percent')
                ? '${s.text('month_margin_percent')}%'
                : '—',
            negativeMargin: monthGrossProfit < 0,
          ),
        ],
        DashboardCard(
          icon: Icons.calendar_today_outlined,
          title: 'Last 7 days',
          subtitle: 'Daily transactions and sales totals',
          child: s.rows('last_7_days').isEmpty
              ? const Text('No daily sales data available.')
              : Column(
                  children: [
                    for (final row in s.rows('last_7_days').reversed)
                      FactLine(
                        '${_date(row['date']) == null ? row['date'] : formatWeekdayDate(_date(row['date'])!)}'
                        ' · ${_plural(_num(row['transactions']).toInt(), 'transaction')}',
                        formatPeso(_num(row['total'])),
                      ),
                  ],
                ),
        ),
        ItemListCard(
          icon: Icons.star_outline,
          title: 'Best sellers this month',
          empty: 'No sales this month yet.',
          items: [
            for (final (index, row) in s.rows('top_products_month').indexed)
              DashboardItem(
                title: '${row['name']}',
                status: 'Qty ${formatQuantity(_num(row['qty']))} sold',
                chip: '#${index + 1}',
                facts: [
                  ('Sold', formatQuantity(_num(row['qty']))),
                  ('Sales', formatPeso(_num(row['total']))),
                ],
              ),
          ],
        ),
      ],
      side: [
        DashboardCard(
          icon: Icons.person_outline,
          title: 'Cashiers today',
          child: BreakdownBars(
            empty: 'No sales rung today.',
            entries: [
              for (final row in s.rows('by_cashier_today'))
                BreakdownEntry(
                  label: '${row['name']} (${row['transactions']})',
                  value: _num(row['total']),
                  display: formatPesoWhole(_num(row['total'])),
                ),
            ],
          ),
        ),
        if (s.rows('by_payment_method_month').isNotEmpty)
          DonutChart(
            key: const ValueKey('admin-dashboard-payment-donut'),
            title: 'Payment methods this month',
            subtitle: 'Cleared tender share',
            centerLabel: 'Cleared',
            centerValue: formatPesoWhole(
              s
                  .rows('by_payment_method_month')
                  .fold<double>(0, (sum, r) => sum + _num(r['total'])),
            ),
            slices: [
              for (final row in s.rows('by_payment_method_month'))
                ShareSlice(
                  label:
                      '${TenderMethod.labelFor('${row['method']}')} (${row['count']})',
                  value: _num(row['total']),
                  amountText: formatPesoWhole(_num(row['total'])),
                ),
            ],
          ),
      ],
    );
  }
}

class _InventoryTab extends StatelessWidget {
  const _InventoryTab(this.s);
  final DashboardSection s;

  static StatusTone _alertTone(Object? code) => switch ('$code') {
    'OUT_OF_STOCK' => StatusTone.error,
    _ => StatusTone.warning,
  };

  @override
  Widget build(BuildContext context) {
    final out = s.count('out_of_stock');
    final low = s.count('low_stock');
    final expiring = s.count('expiring');
    final drafts = s.count('draft_purchase_orders');
    return _tab(
      'tab-inventory',
      readOnly:
          'The Stock Manager records deliveries, counts and adjustments. '
          'This tab only shows them.',
      tiles: [
        StitchKpiCard(
          label: 'Stock value at cost',
          icon: Icons.inventory_2_outlined,
          value: _whole(s, 'stock_cost'),
          tone: StitchTone.primary,
          pillLabel: 'at retail ${_whole(s, 'stock_retail')}',
          pillTone: StitchTone.primary,
        ),
        StitchKpiCard(
          label: 'Products on sale',
          icon: Icons.sell_outlined,
          value: _count(s, 'products_active'),
          tone: StitchTone.success,
          pillLabel: '${_count(s, 'products_archived')} archived',
          pillTone: StitchTone.neutral,
        ),
        StitchKpiCard(
          label: 'Open stock alerts',
          icon: Icons.notifications_none,
          value: _count(s, 'open_alerts'),
          tone: out > 0
              ? StitchTone.danger
              : (low > 0 || expiring > 0
                    ? StitchTone.warning
                    : StitchTone.success),
          valueColor: out > 0 ? StitchColors.danger : null,
          pillLabel: out > 0
              ? '$out out of stock'
              : (low > 0 ? '$low low stock' : 'All healthy'),
          pillTone: out > 0
              ? StitchTone.danger
              : (low > 0 ? StitchTone.warning : StitchTone.success),
        ),
        StitchKpiCard(
          label: 'Purchase orders open',
          icon: Icons.shopping_cart_outlined,
          value: _count(s, 'open_purchase_orders'),
          tone: drafts > 0 ? StitchTone.warning : StitchTone.neutral,
          pillLabel: _plural(drafts, 'draft'),
          pillTone: drafts > 0 ? StitchTone.warning : StitchTone.neutral,
        ),
      ],
      main: [
        AttentionCard(
          clearReason: 'Nothing is out of stock, running low or expiring.',
          items: [
            if (out > 0)
              AttentionItem(
                level: AttentionLevel.urgent,
                title: '${_plural(out, 'product')} out of stock',
                why: 'The till cannot sell them until stock is received.',
              ),
            if (low > 0)
              AttentionItem(
                level: AttentionLevel.warning,
                title: '${_plural(low, 'product')} running low',
                why: 'Below the reorder level; order before they run out.',
              ),
            if (expiring > 0)
              AttentionItem(
                level: AttentionLevel.warning,
                title: '${_plural(expiring, 'batch', 'batches')} expiring',
                why: 'Sell or write them off before the date passes.',
              ),
            if (drafts > 0)
              AttentionItem(
                level: AttentionLevel.warning,
                title: '${_plural(drafts, 'purchase order')} still a draft',
                why: 'A draft has not been sent to the supplier yet.',
              ),
          ],
        ),
        ItemListCard(
          icon: Icons.notifications_none,
          title: 'Open stock alerts',
          subtitle: 'Newest first',
          empty: 'No open alerts.',
          items: [
            for (final row in s.rows('alerts'))
              DashboardItem(
                title: '${row['message']}',
                status: 'Raised ${_when(row['created_at'])}',
                chip: '${row['type']}',
                chipTone: _alertTone(row['code']),
                late: row['code'] == 'OUT_OF_STOCK',
                facts: [
                  ('Alert', '${row['type']}'),
                  ('Raised', _when(row['created_at'])),
                ],
              ),
          ],
        ),
      ],
      side: [
        DashboardCard(
          icon: Icons.shelves,
          title: 'Stock value by shelf',
          subtitle: 'At cost',
          child: BreakdownBars(
            empty: 'No stock on any shelf.',
            entries: [
              for (final row in s.rows('by_location'))
                BreakdownEntry(
                  label: '${row['name']}',
                  value: _num(row['cost']),
                  display: formatPesoWhole(_num(row['cost'])),
                ),
            ],
          ),
        ),
        if (s.rows('by_location').isNotEmpty)
          DonutChart(
            key: const ValueKey('admin-dashboard-shelf-donut'),
            title: 'Shelf share',
            subtitle: 'Landed FIFO cost distribution',
            centerLabel: 'At cost',
            centerValue: _whole(s, 'stock_cost'),
            slices: [
              for (final row in s.rows('by_location'))
                ShareSlice(
                  label: '${row['name']}',
                  value: _num(row['cost']),
                  amountText: formatPesoWhole(_num(row['cost'])),
                ),
            ],
          ),
        if (out > 0 || low > 0 || expiring > 0)
          ShareSplitChart(
            key: const ValueKey('admin-dashboard-alert-split'),
            title: 'Alert breakdown',
            subtitle: 'Active stock exceptions',
            slices: [
              if (out > 0)
                ShareSlice(
                  label: 'Out of stock',
                  value: out.toDouble(),
                  amountText: '$out',
                ),
              if (low > 0)
                ShareSlice(
                  label: 'Low stock',
                  value: low.toDouble(),
                  amountText: '$low',
                ),
              if (expiring > 0)
                ShareSlice(
                  label: 'Expiring batches',
                  value: expiring.toDouble(),
                  amountText: '$expiring',
                ),
            ],
          ),
        DashboardCard(
          icon: Icons.swap_horiz,
          title: 'Last 7 days',
          child: Column(
            children: [
              FactLine('Stock adjustments', _count(s, 'adjustments_7d')),
              FactLine('Transfers between shelves', _count(s, 'transfers_7d')),
            ],
          ),
        ),
      ],
    );
  }
}

class _BodegaTab extends StatelessWidget {
  const _BodegaTab(this.s);
  final DashboardSection s;

  @override
  Widget build(BuildContext context) {
    final pending = s.rows('pending_delivery_list');
    final pendingCount = s.count('pending_deliveries');
    final pickups = s.count('open_pickups');
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final waitedLong = pending.where((row) {
      final at = _date(row['received_at']);
      return at != null && at.isBefore(yesterday);
    }).length;
    final writeOffs = s.count('write_offs_month');
    return _tab(
      'tab-bodega',
      readOnly:
          'The Bodega checker confirms deliveries and releases pick-ups on '
          'the phone. This tab only shows them.',
      tiles: [
        StitchKpiCard(
          label: 'Waiting for pick-up',
          icon: Icons.outbox_outlined,
          value: _count(s, 'open_pickups'),
          tone: pickups > 0 ? StitchTone.warning : StitchTone.primary,
          pillLabel: 'paid, not fully collected',
          pillTone: pickups > 0 ? StitchTone.warning : StitchTone.neutral,
        ),
        StitchKpiCard(
          label: 'Deliveries to check',
          icon: Icons.local_shipping_outlined,
          value: _count(s, 'pending_deliveries'),
          tone: waitedLong > 0
              ? StitchTone.danger
              : (pendingCount > 0 ? StitchTone.warning : StitchTone.success),
          valueColor: waitedLong > 0 ? StitchColors.danger : null,
          pillLabel: 'not stock until checked',
          pillTone: waitedLong > 0
              ? StitchTone.danger
              : (pendingCount > 0 ? StitchTone.warning : StitchTone.neutral),
        ),
        StitchKpiCard(
          label: 'Releases today',
          icon: Icons.done_all,
          value: _count(s, 'releases_today'),
          tone: StitchTone.success,
          pillLabel: 'Bodega dispatches',
          pillTone: StitchTone.success,
        ),
        StitchKpiCard(
          label: 'Write-offs this month',
          icon: Icons.report_gmailerrorred_outlined,
          value: _count(s, 'write_offs_month'),
          tone: writeOffs > 0 ? StitchTone.danger : StitchTone.neutral,
          valueColor: writeOffs > 0 ? StitchColors.danger : null,
          pillLabel:
              '${_plural(s.count('deliveries_checked_month'), 'delivery', 'deliveries')} checked',
          pillTone: StitchTone.neutral,
        ),
      ],
      main: [
        AttentionCard(
          clearReason: 'Every Bodega delivery has been checked.',
          items: [
            if (waitedLong > 0)
              AttentionItem(
                level: AttentionLevel.urgent,
                title:
                    '${_plural(waitedLong, 'delivery', 'deliveries')} '
                    'waiting over a day',
                why:
                    'The goods cannot be sold until the checker confirms '
                    'them.',
              ),
            if (pendingCount > waitedLong)
              AttentionItem(
                level: AttentionLevel.warning,
                title:
                    '${_plural(pendingCount - waitedLong, 'delivery', 'deliveries')} '
                    'waiting for the Bodega checker',
                why: 'Not counted as stock until the quantity is confirmed.',
              ),
            if (pickups > 0)
              AttentionItem(
                level: AttentionLevel.warning,
                title: '${_plural(pickups, 'receipt')} not fully picked up',
                why:
                    'Paid goods still in the Bodega; the stock is held '
                    'for them.',
              ),
          ],
        ),
        ItemListCard(
          icon: Icons.local_shipping_outlined,
          title: 'Deliveries to check',
          subtitle: 'Oldest first',
          empty: 'Nothing waiting for the checker.',
          items: [
            for (final row in pending)
              DashboardItem(
                title: '${row['number']} · ${row['supplier']}',
                status: 'Received ${_when(row['received_at'])}',
                late: (_date(row['received_at']) ?? DateTime.now()).isBefore(
                  yesterday,
                ),
                chip: 'For checking',
                chipTone: StatusTone.warning,
                facts: [
                  ('Supplier', '${row['supplier']}'),
                  (
                    'Delivery receipt',
                    '${row['delivery_receipt_no']}'.isEmpty
                        ? '—'
                        : '${row['delivery_receipt_no']}',
                  ),
                  ('Lines', '${row['lines']}'),
                  ('Delivered', formatQuantity(_num(row['delivered_qty']))),
                ],
              ),
          ],
        ),
        ItemListCard(
          icon: Icons.outbox_outlined,
          title: 'Latest releases',
          empty: 'Nothing released from the Bodega yet.',
          items: [
            for (final row in s.rows('recent_releases'))
              DashboardItem(
                title: '${row['number']}',
                status: 'Receipt ${row['receipt']} · to ${row['received_by']}',
                chip: 'Released',
                chipTone: StatusTone.success,
                facts: [
                  ('Receipt', '${row['receipt']}'),
                  ('Picked up by', '${row['received_by']}'),
                  ('When', _when(row['when'])),
                ],
              ),
          ],
        ),
      ],
      side: [
        DashboardCard(
          icon: Icons.fact_check_outlined,
          title: 'Checker activity',
          child: BreakdownBars(
            empty: 'No activity yet.',
            entries: [
              BreakdownEntry(
                label: 'Releases today',
                value: s.count('releases_today').toDouble(),
                display: _count(s, 'releases_today'),
                tone: StatusTone.success,
              ),
              BreakdownEntry(
                label: 'Deliveries checked this month',
                value: s.count('deliveries_checked_month').toDouble(),
                display: _count(s, 'deliveries_checked_month'),
              ),
              BreakdownEntry(
                label: 'Waiting to be checked',
                value: pendingCount.toDouble(),
                display: '$pendingCount',
                tone: StatusTone.warning,
              ),
              BreakdownEntry(
                label: 'Write-offs this month',
                value: writeOffs.toDouble(),
                display: '$writeOffs',
                tone: StatusTone.error,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FinanceTab extends StatelessWidget {
  const _FinanceTab(this.s);
  final DashboardSection s;

  @override
  Widget build(BuildContext context) {
    final overdueBills = s.count('payables_overdue_count');
    final overdueUtang = s.count('receivables_overdue_count');
    final dueSoon = s.money('payables_due_7d');
    final customerCheques = s.count('customer_cheques_pending');
    final ourCheques = s.count('supplier_cheques_issued');
    final today = DateUtils.dateOnly(DateTime.now());
    return _tab(
      'tab-finance',
      readOnly:
          'Cashiers collect utang and the Store Manager pays supplier bills. '
          'This tab only shows them.',
      tiles: [
        StitchKpiCard(
          label: 'Customers owe (utang)',
          icon: Icons.people_outline,
          value: _whole(s, 'receivables_total'),
          tone: StitchTone.primary,
          pillLabel: _plural(s.count('receivables_count'), 'open account'),
          pillTone: StitchTone.primary,
        ),
        StitchKpiCard(
          label: 'Overdue utang',
          icon: Icons.event_busy_outlined,
          value: _whole(s, 'receivables_overdue'),
          tone: overdueUtang > 0 ? StitchTone.danger : StitchTone.success,
          valueColor: overdueUtang > 0 ? StitchColors.danger : null,
          pillLabel: _plural(overdueUtang, 'account'),
          pillTone: overdueUtang > 0 ? StitchTone.danger : StitchTone.success,
        ),
        StitchKpiCard(
          label: 'We owe suppliers',
          icon: Icons.storefront_outlined,
          value: _whole(s, 'payables_total'),
          tone: StitchTone.primary,
          pillLabel: _plural(s.count('payables_count'), 'open bill'),
          pillTone: StitchTone.neutral,
        ),
        StitchKpiCard(
          label: 'Bills due in 7 days',
          icon: Icons.event_outlined,
          value: _whole(s, 'payables_due_7d'),
          tone: overdueBills > 0
              ? StitchTone.danger
              : (dueSoon > 0 ? StitchTone.warning : StitchTone.success),
          pillLabel: 'overdue ${_whole(s, 'payables_overdue')}',
          pillTone: overdueBills > 0 ? StitchTone.danger : StitchTone.neutral,
        ),
      ],
      main: [
        AttentionCard(
          clearReason: 'No overdue bills or utang, nothing due this week.',
          items: [
            if (overdueBills > 0)
              AttentionItem(
                level: AttentionLevel.urgent,
                title:
                    '${_plural(overdueBills, 'supplier bill')} overdue · '
                    '${_whole(s, 'payables_overdue')}',
                why: 'Late payment can stop a supplier delivering on terms.',
              ),
            if (overdueUtang > 0)
              AttentionItem(
                level: AttentionLevel.urgent,
                title:
                    '${_plural(overdueUtang, 'customer')} past due · '
                    '${_whole(s, 'receivables_overdue')}',
                why: 'Money the shop is owed; follow up before it grows.',
              ),
            if (dueSoon > 0)
              AttentionItem(
                level: AttentionLevel.warning,
                title: '${formatPesoWhole(dueSoon)} in bills due this week',
                why: 'Have the cash or cheques ready before the due dates.',
              ),
            if (customerCheques > 0)
              AttentionItem(
                level: AttentionLevel.warning,
                title:
                    '${_plural(customerCheques, 'customer cheque')} not '
                    'cleared',
                why: 'Not money in the bank until the cheque clears.',
              ),
            if (ourCheques > 0)
              AttentionItem(
                level: AttentionLevel.warning,
                title: '${_plural(ourCheques, 'cheque')} we issued not cleared',
                why: 'Keep enough in the bank until the supplier cashes it.',
              ),
          ],
        ),
        ItemListCard(
          icon: Icons.receipt_long_outlined,
          title: 'Open supplier bills',
          subtitle: 'Soonest due first',
          empty: 'No unpaid supplier bills.',
          items: [for (final row in s.rows('open_bills')) _bill(row, today)],
        ),
        ItemListCard(
          icon: Icons.person_search_outlined,
          title: 'Overdue utang',
          empty: 'No customer is past due.',
          items: [
            for (final row in s.rows('overdue_receivables'))
              DashboardItem(
                title: '${row['customer']}',
                status: 'Was due ${_day(row['due_date'])}',
                late: true,
                chip: formatPeso(_num(row['balance'])),
                chipTone: StatusTone.error,
                facts: [
                  ('Due', _day(row['due_date'])),
                  ('Balance', formatPeso(_num(row['balance']))),
                ],
              ),
          ],
        ),
      ],
      side: [
        DashboardCard(
          icon: Icons.storefront_outlined,
          title: 'Owed by supplier',
          subtitle: 'Unpaid balance',
          child: BreakdownBars(
            empty: 'Nothing owed to suppliers.',
            entries: [
              for (final row in s.rows('payables_by_supplier'))
                BreakdownEntry(
                  label: '${row['supplier']}',
                  value: _num(row['balance']),
                  display: formatPesoWhole(_num(row['balance'])),
                ),
            ],
          ),
        ),
        if (s.rows('payables_by_supplier').isNotEmpty)
          DonutChart(
            key: const ValueKey('admin-dashboard-payables-donut'),
            title: 'Supplier balance share',
            subtitle: 'Unpaid payables breakdown',
            centerLabel: 'Payables',
            centerValue: _whole(s, 'payables_total'),
            slices: [
              for (final row in s.rows('payables_by_supplier').take(6))
                ShareSlice(
                  label: '${row['supplier']}',
                  value: _num(row['balance']),
                  amountText: formatPesoWhole(_num(row['balance'])),
                ),
            ],
          ),
        if (s.money('receivables_total') > 0 || s.money('payables_total') > 0)
          ShareSplitChart(
            key: const ValueKey('admin-dashboard-ar-ap-split'),
            title: 'Receivables vs. Payables',
            subtitle: 'Open utang owed to shop vs. unpaid supplier bills',
            slices: [
              if (s.money('receivables_total') > 0)
                ShareSlice(
                  label: 'Customers owe (utang)',
                  value: s.money('receivables_total'),
                  amountText: _whole(s, 'receivables_total'),
                ),
              if (s.money('payables_total') > 0)
                ShareSlice(
                  label: 'We owe suppliers',
                  value: s.money('payables_total'),
                  amountText: _whole(s, 'payables_total'),
                ),
            ],
          ),
        DashboardCard(
          icon: Icons.payments_outlined,
          title: 'This month',
          child: BreakdownBars(
            empty: '',
            entries: [
              BreakdownEntry(
                label: 'Collected from customers',
                value: s.money('collections_month'),
                display: _whole(s, 'collections_month'),
                tone: StatusTone.success,
              ),
              BreakdownEntry(
                label: 'Paid to suppliers',
                value: s.money('supplier_payments_month'),
                display: _whole(s, 'supplier_payments_month'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static DashboardItem _bill(Map<String, dynamic> row, DateTime today) {
    final due = _date(row['due_date']);
    final overdue = row['overdue'] == true;
    final soon = !overdue && due != null && due.difference(today).inDays <= 7;
    final reference = '${row['reference'] ?? ''}';
    final dueLabel = due == null ? 'No due date' : _day(row['due_date']);
    final statusText = overdue
        ? 'Overdue since ${_day(row['due_date'])} · '
              '${formatPeso(_num(row['balance']))} left'
        : due == null
        ? 'No due date · ${formatPeso(_num(row['balance']))} left'
        : 'Due ${_day(row['due_date'])} · '
              '${formatPeso(_num(row['balance']))} left';
    return DashboardItem(
      title: '${row['supplier']}',
      status: statusText,
      late: overdue,
      chip: overdue ? 'Overdue' : (soon ? 'Due soon' : 'Open'),
      chipTone: overdue
          ? StatusTone.error
          : (soon ? StatusTone.warning : StatusTone.neutral),
      facts: [
        ('Delivery receipt', reference.isEmpty ? '—' : reference),
        ('Received', _day(row['received_date'])),
        ('Due', dueLabel),
        ('Bill total', formatPeso(_num(row['total']))),
        ('Balance', formatPeso(_num(row['balance']))),
      ],
    );
  }
}

class _VelocitySummaryStrip extends StatelessWidget {
  const _VelocitySummaryStrip({
    required this.peak7d,
    required this.total7d,
    required this.monthMargin,
    required this.negativeMargin,
  });

  final String peak7d;
  final String total7d;
  final String monthMargin;
  final bool negativeMargin;

  @override
  Widget build(BuildContext context) {
    final items = [
      _VelocityStat(label: '7-DAY PEAK', value: peak7d),
      _VelocityStat(label: '7-DAY TOTAL', value: total7d),
      _VelocityStat(
        label: 'MONTH MARGIN %',
        value: monthMargin,
        valueColor: monthMargin == '—'
            ? StitchColors.inkMuted
            : (negativeMargin ? StitchColors.danger : StitchColors.successInk),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: StitchColors.surfaceCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StitchColors.divider),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Wrap(spacing: 16, runSpacing: 10, children: items);
          }
          return Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: items[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _VelocityStat extends StatelessWidget {
  const _VelocityStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: StitchColors.inkMuted,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: valueColor ?? StitchColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

String _shortDay(Object? raw) {
  final dt = _date(raw);
  if (dt == null) return '${raw ?? ''}';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}';
}
