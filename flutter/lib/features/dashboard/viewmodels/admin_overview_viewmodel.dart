import 'package:client/data/models/reports.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:flutter/foundation.dart';

/// Owns the Admin Overview screen's live sections.
///
/// The overview aggregates three reads: today's sales summary (reports),
/// the latest sales transactions, and — through the shared
/// `InventoryViewmodel`, loaded by the page — stock counts and alerts.
/// Sections with no wired source do not render: the old screen's "Active
/// users" card and static "Sales chart" text had no backend behind them,
/// and a fabricated number is worse than a missing card.
class AdminOverviewViewmodel extends ChangeNotifier {
  AdminOverviewViewmodel({ReportsService? reports, SalesService? sales})
    : _reports = reports ?? ReportsService(),
      _sales = sales ?? SalesService();

  final ReportsService _reports;
  final SalesService _sales;

  SalesSummary? _today;
  List<TransactionRecord> _recent = const [];
  bool _isLoading = false;
  String? _loadError;

  SalesSummary? get today => _today;
  List<TransactionRecord> get recentTransactions => List.unmodifiable(_recent);
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  bool get hasLoaded => _today != null;

  /// Loads today's sales summary plus the latest transactions.
  ///
  /// A failed load keeps the rows already shown: an empty screen would read
  /// as "no business today", which is a different and far more dangerous
  /// statement than "this did not load".
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final results = await Future.wait([
        _reports.fetchSalesSummary(from: day, to: day),
        _sales.fetchTransactions(),
      ]);
      _today = results[0] as SalesSummary;
      final rows = results[1] as List<TransactionRecord>;
      _recent = rows.take(5).toList();
      _loadError = null;
    } on ReportsServiceException catch (error) {
      _loadError = error.message;
    } on SalesServiceException catch (error) {
      _loadError = error.message;
    } on FormatException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
