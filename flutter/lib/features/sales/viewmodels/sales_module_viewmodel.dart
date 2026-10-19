import 'package:client/data/models/customer.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/sales_module.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:flutter/foundation.dart';

/// Owns the sales role's quotation and order screens.
///
/// Decision 05: this is the CANONICAL stack for quotations and orders — and
/// since Phase 6 gave them real backends, it reads live endpoints instead of
/// the mock rows it carried before. The shapes stay: pages render
/// `SalesQuotation`/`SalesOrderRecord` exactly as before.
class SalesModuleViewmodel extends ChangeNotifier {
  SalesModuleViewmodel({
    SalesService? service,
    CustomerService? customerService,
  }) : _service = service ?? SalesService(),
       _customers = customerService ?? CustomerService();

  final SalesService _service;
  final CustomerService _customers;

  List<SalesQuotation> _quotations = const [];
  List<SalesOrderRecord> _orders = const [];
  bool _isLoading = false;
  String? _loadError;

  List<SalesQuotation> get quotations => List.unmodifiable(_quotations);
  List<SalesOrderRecord> get orders => List.unmodifiable(_orders);
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  bool get hasLoaded => _quotations.isNotEmpty || _orders.isNotEmpty;

  /// Loads quotations and orders, joining customer display names.
  ///
  /// A failed load keeps the rows already shown: an empty list would read as
  /// "no quotations", which is a different and far more dangerous statement
  /// than "this did not load".
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _service.fetchQuotations(),
        _service.fetchSalesOrders(),
        _customers.fetchCustomers(),
      ]);
      final quotes = results[0] as List<QuotationRecord>;
      final orderRows = results[1] as List<SalesOrderRow>;
      final customers = results[2] as List<Customer>;
      final names = {for (final c in customers) c.id: c.name};
      String nameOf(int id) => names[id] ?? 'Customer #$id';
      _quotations = [
        for (final q in quotes)
          SalesQuotation(
            q.number,
            nameOf(q.customerId),
            DateTime.parse(q.createdAt),
            // No expiry on the wire means none set: fall back to creation.
            DateTime.tryParse(q.validUntil ?? '') ??
                DateTime.parse(q.createdAt),
            q.items.fold<double>(0, (sum, i) => sum + i.qty * i.unitPrice),
            _quoteStatus(q.status),
          ),
      ];
      _orders = [
        for (final o in orderRows)
          SalesOrderRecord(
            o.number,
            nameOf(o.customerId),
            DateTime.parse(o.createdAt),
            o.total,
            _orderStatus(o.status),
          ),
      ];
      _loadError = null;
    } on SalesServiceException catch (error) {
      _loadError = error.message;
    } on CustomerServiceException catch (error) {
      _loadError = error.message;
    } on FormatException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  SalesQuoteStatus _quoteStatus(String api) {
    switch (api) {
      case 'DRAFT':
        return SalesQuoteStatus.draft;
      case 'SENT':
        return SalesQuoteStatus.sent;
      case 'ACCEPTED':
        return SalesQuoteStatus.accepted;
      case 'EXPIRED':
        return SalesQuoteStatus.expired;
      default:
        throw FormatException('Unknown quotation status: "$api"');
    }
  }

  SalesOrderStatus _orderStatus(String api) {
    switch (api) {
      case 'CONFIRMED':
        return SalesOrderStatus.confirmed;
      case 'PROCESSING':
        return SalesOrderStatus.processing;
      case 'READY':
        return SalesOrderStatus.ready;
      case 'COMPLETED':
        return SalesOrderStatus.completed;
      default:
        throw FormatException('Unknown order status: "$api"');
    }
  }
}
