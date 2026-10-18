import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:flutter/foundation.dart';

/// Owns the admin Reports screen: four tabs, one report loaded at a time.
///
/// Decision 16 (as amended): Sales · Valuation · Movements · Requisitions, each
/// tab loading only when first shown. Sales and movements take a from/to range;
/// valuation and requisition history do not. A failure stays on its own tab —
/// one broken report must not blank the other three.
class AdminReportsViewmodel extends ChangeNotifier {
  AdminReportsViewmodel({ReportsRepository? repository})
    : _repository = repository ?? ReportsRepository();

  final ReportsRepository _repository;

  /// Tab order: 0 Sales, 1 Valuation, 2 Movements, 3 Requisitions.
  int _selectedTab = 0;
  int get selectedTab => _selectedTab;

  final Set<int> _loaded = {};
  final Set<int> _loading = {};
  final Map<int, String> _errors = {};

  SalesSummary? sales;
  InventoryValuation? valuation;
  StockMovements? movements;
  RequisitionHistory? history;

  String? _from;
  String? _to;

  bool isLoadingTab(int tab) => _loading.contains(tab);

  /// Why the tab's report failed; null when it loaded or was never tried.
  String? errorFor(int tab) => _errors[tab];

  /// Loads the selected tab on first show.
  Future<void> load() => _loadTab(_selectedTab);

  /// Switches tab, loading it the first time it is shown.
  Future<void> selectTab(int tab) async {
    _selectedTab = tab;
    notifyListeners();
    await _loadTab(tab);
  }

  /// A range change reloads the two ranged tabs; the others have no range.
  Future<void> setRange(String? from, String? to) async {
    _from = from;
    _to = to;
    _loaded.removeAll({0, 2});
    await _loadTab(0);
    if (_selectedTab == 2) await _loadTab(2);
  }

  Future<void> reload() async {
    _loaded.remove(_selectedTab);
    await _loadTab(_selectedTab);
  }

  Future<void> _loadTab(int tab) async {
    if (_loaded.contains(tab) || _loading.contains(tab)) return;
    _loading.add(tab);
    _errors.remove(tab);
    notifyListeners();
    try {
      switch (tab) {
        case 0:
          sales = await _repository.fetchSalesSummary(from: _from, to: _to);
        case 1:
          valuation = await _repository.fetchInventoryValuation();
        case 2:
          movements = await _repository.fetchStockMovements(
            from: _from,
            to: _to,
          );
        case 3:
          history = await _repository.fetchRequisitionHistory();
      }
      _loaded.add(tab);
    } on ReportsServiceException catch (error) {
      _errors[tab] = error.message;
    } finally {
      _loading.remove(tab);
      notifyListeners();
    }
  }
}
