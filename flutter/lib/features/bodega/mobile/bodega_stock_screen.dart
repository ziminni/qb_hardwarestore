import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_shell.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_widgets.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The phone's Bodega stock (owner 2026-11-18): the brand header with a back
/// arrow, a search, All / Low stock, and one card per product showing only its
/// stock quantity (owner 2026-11-19). Read only.
class BodegaStockScreen extends StatelessWidget {
  const BodegaStockScreen({super.key, this.viewmodel});

  final BodegaViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? BodegaViewmodel())..loadStock(),
    child: const _StockBody(),
  );
}

class _StockBody extends StatefulWidget {
  const _StockBody();

  @override
  State<_StockBody> createState() => _StockBodyState();
}

class _StockBodyState extends State<_StockBody> {
  final _search = TextEditingController();
  bool _lowOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<BodegaViewmodel>();
    final needle = _search.text.trim().toLowerCase();
    final all = viewmodel.stock;
    final low = all.where((row) => row.isLow).length;
    final rows = [
      for (final row in all)
        if ((!_lowOnly || row.isLow) &&
            (needle.isEmpty ||
                row.label.toLowerCase().contains(needle) ||
                row.category.toLowerCase().contains(needle)))
          row,
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            BodegaHeader(
              title: 'Bodega stock',
              name: '',
              subtitle: '',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: viewmodel.loadStock,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search a product or category',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      setState(() => _search.clear()),
                                ),
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('All (${all.length})'),
                            selected: !_lowOnly,
                            onSelected: (_) => setState(() => _lowOnly = false),
                          ),
                          ChoiceChip(
                            avatar: low > 0
                                ? const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: AppColors.warningText,
                                  )
                                : null,
                            label: Text('Low stock ($low)'),
                            selected: _lowOnly,
                            onSelected: (_) => setState(() => _lowOnly = true),
                          ),
                        ],
                      ),
                    ),
                    if (viewmodel.loadError case final error?)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          error,
                          style: const TextStyle(color: AppColors.errorText),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (viewmodel.isLoading && all.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (rows.isEmpty)
                      MobileCard(
                        child: EmptyNote(
                          all.isEmpty
                              ? 'Nothing is kept in the Bodega yet.'
                              : _lowOnly && needle.isEmpty
                              ? 'No product is running low.'
                              : 'No product matches "${_search.text.trim()}".',
                        ),
                      )
                    else
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _StockCard(row: row),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One product: its name on the left, its stock quantity on the right.
class _StockCard extends StatelessWidget {
  const _StockCard({required this.row});
  final BodegaStockRow row;

  @override
  Widget build(BuildContext context) {
    return MobileCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.productName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    if (row.variantName.isNotEmpty) row.variantName,
                    if (row.category.isNotEmpty) row.category,
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if (row.isLow)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Low stock',
                      style: TextStyle(
                        color: AppColors.warningText,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatQuantity(row.physical),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                row.unit,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
