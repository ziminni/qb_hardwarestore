import 'package:client/core/constants/app_areas.dart';

/// The three groups the catalogues home draws, in reading order.
///
/// The reading order is the roll-up the Reports suite promises: sales money
/// first, then stock, then the per-ticket KPIs derived from sales.
enum ReportSection {
  sales('SALES'),
  inventory('INVENTORY'),
  kpis('KPIs');

  const ReportSection(this.label);

  final String label;
}

/// One card on the catalogue home: a report a reader can pick.
///
/// [id] is the card's identity and the `:reportId` the shared viewer loads;
/// [available] is false for a P1 report that has no endpoint behind it yet, so
/// the card renders disabled with a "P1" tag instead of opening a viewer over
/// nothing (a P1 backend landing flips one flag, nothing else).
class ReportDefinition {
  const ReportDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.section,
    this.available = true,
    this.readers,
  });

  final String id;
  final String title;
  final String description;
  final ReportSection section;
  final bool available;

  /// The areas whose accounts the server lets read this report, when that is
  /// narrower than its section; null means everyone who sees the section. A
  /// card the account cannot open is not drawn, so nobody lands on "You do not
  /// have access to reports" (requisition history is Store Manager / Admin).
  final Set<String>? readers;

  /// Whether an account holding [areas] may open this report.
  bool readableBy(Set<String> areas) =>
      readers == null || readers!.any(areas.contains);
}

/// Every report the catalogue offers, grouped by [ReportSection] in the order
/// the screen draws them.
///
/// The [available] entries are the endpoints that exist today
/// (`/api/v1/reports/*`) — the six originals, the seven P1 sales detail reports
/// and the ten P2 inventory reports. The three KPI cards stay disabled: their
/// numbers are drawn as tiles inside the shared sales-summary viewer, where the
/// arithmetic behind them is on screen, not as separate reports.
const List<ReportDefinition> reportCatalogue = [
  // SALES
  ReportDefinition(
    id: 'sales-summary',
    title: 'Sales summary',
    description:
        'Daily totals: transactions, invoice total, discounts and VAT.',
    section: ReportSection.sales,
  ),
  ReportDefinition(
    id: 'vat-summary',
    title: 'VAT & OR summary',
    description:
        'Whole VAT against OR-tagged sales, by day, week or month.',
    section: ReportSection.sales,
  ),
  ReportDefinition(
    id: 'item-wise',
    title: 'Item-wise sales',
    description: 'Units and pesos per item and category.',
    section: ReportSection.sales,
  ),
  ReportDefinition(
    id: 'hourly',
    title: 'Hourly sales',
    description: 'Peso volume by hour of the day.',
    section: ReportSection.sales,
  ),
  ReportDefinition(
    id: 'cashier',
    title: 'Cashier performance',
    description: 'Sales, transaction count and average ticket per cashier.',
    section: ReportSection.sales,
  ),
  ReportDefinition(
    id: 'bill-wise',
    title: 'Bill-wise sales',
    description: 'Every order slip with its items and total.',
    section: ReportSection.sales,
  ),
  ReportDefinition(
    id: 'returns',
    title: 'Returns & exchanges',
    description: 'Refunds and swaps against the sale they came from.',
    section: ReportSection.sales,
  ),
  ReportDefinition(
    id: 'discounts',
    title: 'Discounts',
    description: 'Line and cart discounts, with who approved them.',
    section: ReportSection.sales,
  ),
  ReportDefinition(
    id: 'voids',
    title: 'Voids',
    description: 'Cancelled and voided sales with the reason recorded.',
    section: ReportSection.sales,
  ),

  // INVENTORY
  ReportDefinition(
    id: 'inventory-valuation',
    title: 'Inventory valuation',
    description:
        'Stock on hand at cost and at retail, by category and location.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'stock-movements',
    title: 'Stock movements',
    description: 'Goods received and adjustments, by day and by reason.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'requisition-history',
    title: 'Requisition history',
    description: 'Project requests with their status and approvals.',
    section: ReportSection.inventory,
    // `requisition_history_view` is IsManagerRole on the server.
    readers: {AppAreas.sales, AppAreas.admin},
  ),

  // P2 inventory detail reports: every one answers through `_paged()` with its
  // totals outside the 50-row page.
  ReportDefinition(
    id: 'grn',
    title: 'Goods received',
    description: 'Every delivery receipt: supplier, items, units and its bill.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'stn',
    title: 'Stock transfers',
    description: 'Stock moved between shelves, with its slip and units.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'batch-age',
    title: 'Batch age',
    description: 'On-hand stock bucketed by how old its batches are (FIFO).',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'shrinkage',
    title: 'Shrinkage & damage',
    description: 'Stock lost per day at landed cost, and shrinkage %.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'adjustments',
    title: 'Stock adjustments',
    description: 'Count corrections and supplier returns with their value.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'reorder',
    title: 'Reorder list',
    description: 'What is at or below its minimum stock, and what to buy.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'dead-stock',
    title: 'Dead stock',
    description: 'Stock that sold nothing in the window and the money tied up.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'fast-slow',
    title: 'Fast & slow movers',
    description: 'The range\'s best and worst selling units, in 20% bands.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'cycle-count',
    title: 'Cycle count',
    description:
        'What each stock count found against what the shelf should hold.',
    section: ReportSection.inventory,
  ),
  ReportDefinition(
    id: 'expiry',
    title: 'Expiry',
    description: 'Expired and expiring batches with the value at risk.',
    section: ReportSection.inventory,
  ),

  // KPIs
  ReportDefinition(
    id: 'abv',
    title: 'Average basket value',
    description: 'Invoice total divided by completed transactions.',
    section: ReportSection.kpis,
    available: false,
  ),
  ReportDefinition(
    id: 'asp',
    title: 'Average selling price',
    description: 'Pesos per unit sold across the range.',
    section: ReportSection.kpis,
    available: false,
  ),
  ReportDefinition(
    id: 'markdown',
    title: 'Markdown %',
    description: 'Discounts given as a share of shelf price.',
    section: ReportSection.kpis,
    available: false,
  ),
];

/// The report with [id], or null for an address no card offers.
ReportDefinition? reportById(String id) {
  for (final report in reportCatalogue) {
    if (report.id == id) return report;
  }
  return null;
}

/// The sections [areas] may see (decision 02-role-visibility).
///
/// Admin and Store Manager (`admin`, `sales`) see everything. The Stock Manager
/// (`inventory`) sees the inventory reports only: Sales, VAT, profit and the
/// sales KPIs are `IsManagerRole` server-side and answer 403 to that account,
/// so drawing the cards would be drawing doors that are locked.
///
/// An empty set means "no area reported" and shows everything — that is the
/// admin's own view, and it keeps a test or a bare harness from rendering a
/// blank catalogue.
Set<ReportSection> reportSectionsFor(Iterable<String> areas) {
  final held = areas.toSet();
  if (held.isEmpty) return ReportSection.values.toSet();
  final manager =
      held.contains(AppAreas.admin) || held.contains(AppAreas.sales);
  if (manager) return ReportSection.values.toSet();
  if (held.contains(AppAreas.inventory)) return {ReportSection.inventory};
  // The till's Cashier has no Reports suite tab (decision 02): nothing to draw.
  return {};
}
