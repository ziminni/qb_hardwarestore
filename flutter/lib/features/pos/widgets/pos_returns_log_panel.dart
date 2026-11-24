import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Unified row model for the Returns & Exchanges audit log (combines RETURN
/// records and EXCHANGE sales sorted newest-first).
class _ReturnLogEntry {
  const _ReturnLogEntry({
    required this.reference,
    required this.date,
    required this.originalRef,
    required this.party,
    required this.itemsSummary,
    required this.amount,
    required this.isExchange,
    required this.statusLabel,
    required this.statusTone,
    required this.reason,
    required this.lines,
  });

  final String reference;
  final DateTime date;
  final String originalRef;
  final String party;
  final String itemsSummary;
  final double amount;
  final bool isExchange;
  final String statusLabel;
  final StatusTone statusTone;
  final String reason;
  final List<SalesDocumentLine> lines;
}

/// Stitch-adapted Returns & Exchanges Audit Log with search, type pills,
/// detail sheet preview, and standard pagination with custom items-per-page.
///
/// Deliberately renders rows in a plain [Column] (bounded by [_pageSize]) so it
/// never nests a scroll view inside [PosReturnsPage]'s single scroll region.
class PosReturnsLogPanel extends StatefulWidget {
  const PosReturnsLogPanel({
    super.key,
    required this.returns,
    required this.exchanges,
    this.isLoading = false,
    this.onRefresh,
  });

  final List<InventoryReturn> returns;
  final List<InventorySale> exchanges;
  final bool isLoading;
  final VoidCallback? onRefresh;

  @override
  State<PosReturnsLogPanel> createState() => _PosReturnsLogPanelState();
}

class _PosReturnsLogPanelState extends State<PosReturnsLogPanel> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageSizeController = TextEditingController(
    text: '10',
  );

  String _query = '';
  String _typeFilter = 'All'; // 'All' | 'Exchanges' | 'Returns'
  int _pageSize = 10;
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    _pageSizeController.dispose();
    super.dispose();
  }

  List<_ReturnLogEntry> get _allEntries {
    final list = <_ReturnLogEntry>[
      for (final r in widget.returns)
        _ReturnLogEntry(
          reference: r.reference,
          date: r.date,
          originalRef: r.relatedReference.isEmpty ? '—' : r.relatedReference,
          party: r.processedBy.isEmpty ? 'Cashier' : r.processedBy,
          itemsSummary: _returnItemsSummary(r),
          amount: r.total,
          isExchange: false,
          statusLabel: r.status.label,
          statusTone: switch (r.status) {
            InventoryReturnStatus.completed => StatusTone.warning,
            InventoryReturnStatus.rejected => StatusTone.error,
            InventoryReturnStatus.approved => StatusTone.info,
            InventoryReturnStatus.pending => StatusTone.neutral,
          },
          reason: r.reason,
          lines: [
            for (final l in r.lines)
              SalesDocumentLine(
                name: l.productName,
                qty: l.quantity.abs(),
                unitPrice: l.unitPrice,
              ),
          ],
        ),
      for (final s in widget.exchanges)
        _ReturnLogEntry(
          reference: s.transactionNo,
          date: s.date,
          originalRef: s.orNumber.isEmpty ? '—' : s.orNumber,
          party: s.customer,
          itemsSummary: _saleItemsSummary(s),
          amount: s.amountDue,
          isExchange: true,
          statusLabel: s.displayStatusLabel,
          statusTone: StatusTone.info,
          reason: s.notes.isEmpty ? 'Item exchange' : s.notes,
          lines: [
            for (final l in s.lines)
              SalesDocumentLine(
                name: l.productName,
                qty: l.quantity.abs(),
                unitPrice: l.unitPrice,
              ),
          ],
        ),
    ];
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  static String _returnItemsSummary(InventoryReturn r) {
    if (r.lines.isEmpty) {
      return '${formatQuantity(r.quantity)} qty';
    }
    final first = r.lines.first.productName;
    final count = r.lines.length;
    return count > 1 ? '$first +${count - 1} more' : '$first (${formatQuantity(r.quantity)})';
  }

  static String _saleItemsSummary(InventorySale s) {
    if (s.lines.isEmpty) return '0 items';
    final first = s.lines.first.productName;
    final count = s.lines.length;
    return count > 1
        ? '$first +${count - 1} more'
        : '$first (${formatQuantity(s.totalQuantity)})';
  }

  List<_ReturnLogEntry> _filteredEntries(List<_ReturnLogEntry> all) {
    final q = _query.trim().toLowerCase();
    return [
      for (final e in all)
        if (_matchesType(e) && _matchesQuery(e, q)) e,
    ];
  }

  bool _matchesType(_ReturnLogEntry e) => switch (_typeFilter) {
    'Exchanges' => e.isExchange,
    'Returns' => !e.isExchange,
    _ => true,
  };

  bool _matchesQuery(_ReturnLogEntry e, String q) {
    if (q.isEmpty) return true;
    final haystack =
        '${e.reference} ${e.originalRef} ${e.party} ${e.itemsSummary} ${e.reason}'
            .toLowerCase();
    return haystack.contains(q);
  }

  void _applyPageSize(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) return;
    final clamped = parsed.clamp(1, 500);
    if (clamped != _pageSize) {
      setState(() {
        _pageSize = clamped;
        _currentPage = 1;
      });
    }
  }

  void _openDetails(BuildContext context, _ReturnLogEntry entry) {
    showSalesDocumentSheet(
      context,
      title: entry.reference,
      fields: [
        ('Type', entry.isExchange ? 'Exchange' : 'Return / Refund'),
        ('Date', formatDateTime(entry.date)),
        ('Original Ref', entry.originalRef),
        (entry.isExchange ? 'Customer' : 'Processed by', entry.party),
        ('Status', entry.statusLabel),
        if (entry.reason.trim().isNotEmpty) ('Reason / Notes', entry.reason),
      ],
      lines: entry.lines,
      total: entry.amount.abs(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _allEntries;
    final filtered = _filteredEntries(all);
    final totalRows = filtered.length;
    final totalPages = totalRows == 0
        ? 1
        : (totalRows + _pageSize - 1) ~/ _pageSize;
    final safePage = _currentPage.clamp(1, totalPages);
    final startIdx = (safePage - 1) * _pageSize;
    final endIdx = (startIdx + _pageSize).clamp(0, totalRows);
    final pageRows = totalRows == 0
        ? const <_ReturnLogEntry>[]
        : filtered.sublist(startIdx, endIdx);

    final exchangeCount = all.where((e) => e.isExchange).length;
    final returnCount = all.where((e) => !e.isExchange).length;

    return AppPanel(
      title: 'Returns & Exchanges Log',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter bar: search + segmented type pills + refresh
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 240, maxWidth: 380),
                child: TextField(
                  key: const ValueKey('returns-log-search'),
                  controller: _searchController,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _currentPage = 1;
                  }),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _query = '';
                                _currentPage = 1;
                              });
                            },
                            icon: const Icon(Icons.close_rounded, size: 16),
                          )
                        : null,
                    hintText: 'Search ref #, original sale, item, or reason...',
                    hintStyle: const TextStyle(fontSize: 13),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        _pill('All', all.length),
                        _pill('Exchanges', exchangeCount),
                        _pill('Returns', returnCount),
                      ],
                    ),
                  ),
                  if (widget.onRefresh != null)
                    IconButton(
                      tooltip: 'Refresh log',
                      onPressed: widget.isLoading ? null : widget.onRefresh,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          if (widget.isLoading && all.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (pageRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                all.isEmpty
                    ? 'No completed returns or exchanges recorded yet.'
                    : 'No entries match these filters.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else ...[
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'REF # & TIME',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'ORIGINAL REF',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'ITEMS & PARTY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'TYPE / STATUS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'AMOUNT',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Paginated rows
            Container(
              decoration: BoxDecoration(
                border: Border(
                  left: const BorderSide(color: AppColors.border),
                  right: const BorderSide(color: AppColors.border),
                  bottom: const BorderSide(color: AppColors.border),
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < pageRows.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: AppColors.border),
                    InkWell(
                      key: ValueKey('returns-log-row-${pageRows[i].reference}'),
                      onTap: () => _openDetails(context, pageRows[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pageRows[i].reference,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  Text(
                                    formatDateTime(pageRows[i].date),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                pageRows[i].originalRef,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pageRows[i].itemsSummary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    pageRows[i].party,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  StatusBadge(
                                    label: pageRows[i].isExchange
                                        ? 'Exchange'
                                        : 'Return',
                                    tone: pageRows[i].isExchange
                                        ? StatusTone.info
                                        : StatusTone.warning,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                formatPeso(pageRows[i].amount),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: pageRows[i].amount < 0
                                      ? AppColors.errorText
                                      : AppColors.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Standard single-row pagination bar with custom items-per-page input
            Container(
              key: const ValueKey('returns-log-pagination'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Showing ${startIdx + 1}–$endIdx of ${formatCount(totalRows)} entries',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Text(
                    'Items per page:',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    height: 30,
                    child: TextField(
                      key: const ValueKey('returns-log-page-size'),
                      controller: _pageSizeController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        filled: true,
                        fillColor: AppColors.cardBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      onChanged: _applyPageSize,
                      onSubmitted: _applyPageSize,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Page $safePage of $totalPages',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const ValueKey('returns-log-prev-page'),
                    tooltip: 'Previous page',
                    onPressed: safePage > 1
                        ? () => setState(() => _currentPage = safePage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('returns-log-next-page'),
                    tooltip: 'Next page',
                    onPressed: safePage < totalPages
                        ? () => setState(() => _currentPage = safePage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String label, int count) {
    final selected = _typeFilter == label;
    return InkWell(
      onTap: () => setState(() {
        _typeFilter = label;
        _currentPage = 1;
      }),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
