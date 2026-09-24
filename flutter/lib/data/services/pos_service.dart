import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:dio/dio.dart';

class PosServiceException implements Exception {
  const PosServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PosService {
  PosService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<List<PosCatalogItem>> fetchCatalog() async {
    try {
      final responses = await Future.wait([_client.get<dynamic>('/api/v1/products/'), _client.get<dynamic>('/api/v1/batches/')]);
      final products = _items(responses[0].data);
      final stock = <int, double>{};
      for (final batch in _items(responses[1].data)) {
        final id = batch['variant'] as int;
        stock[id] = (stock[id] ?? 0) + _number(batch['current_qty']);
      }
      return [
        for (final product in products)
          for (final variantRaw in product['variants'] as List<dynamic>? ?? const [])
            for (final uomRaw in (variantRaw as Map<String, dynamic>)['selling_uoms'] as List<dynamic>? ?? const [])
              _catalogItem(product, variantRaw, uomRaw as Map<String, dynamic>, stock),
      ].where((item) => item.availableBaseStock > 0).toList();
    } on DioException catch (error) {
      throw PosServiceException(_message(error, 'Unable to load POS products.'));
    }
  }

  Future<List<PosCustomer>> fetchCustomers() async {
    try {
      final response = await _client.get<dynamic>('/api/v1/customers/');
      return _items(response.data).where((item) => item['is_active'] != false).map(PosCustomer.fromJson).toList();
    } on DioException catch (error) {
      throw PosServiceException(_message(error, 'Unable to load customers.'));
    }
  }

  Future<PosCheckoutResult> checkout({required int customerId, required List<PosCartLine> lines, required String paymentMethod, required double amountPaid, required String referenceNumber}) async {
    try {
      final response = await _client.post<Map<String, dynamic>>('/api/v1/transactions/', data: {
        'customer': customerId,
        'source': 'WALK_IN',
        'items': lines.map((line) => line.toCheckoutJson()).toList(),
        'payments': [{'method': paymentMethod.toUpperCase(), 'amount_tendered': amountPaid, 'reference_no': referenceNumber}],
      });
      final data = response.data!;
      final receipt = data['receipt'] as Map<String, dynamic>?;
      return PosCheckoutResult(transactionNumber: data['transaction_no'] as String, officialReceiptNumber: receipt?['or_number'] as String? ?? '', createdAt: DateTime.parse(data['trans_date'] as String), total: _number(data['grand_total']));
    } on DioException catch (error) {
      throw PosServiceException(_message(error, 'Checkout failed.'));
    }
  }

  PosCatalogItem _catalogItem(Map<String, dynamic> product, Map<String, dynamic> variant, Map<String, dynamic> uom, Map<int, double> stock) {
    final variantId = variant['id'] as int;
    return PosCatalogItem(variantUomId: uom['id'] as int, variantId: variantId, productName: product['base_name'] as String, variantName: variant['variant_name'] as String, unit: uom['uom_code'] as String? ?? '', barcode: uom['barcode_qr'] as String? ?? '', conversionFactor: _number(uom['conversion_factor']), unitPrice: _number(uom['default_selling_price']), availableBaseStock: stock[variantId] ?? 0);
  }

  List<Map<String, dynamic>> _items(dynamic data) {
    final raw = data is Map<String, dynamic> ? data['results'] : data;
    return (raw as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
  }
  double _number(dynamic value) => double.tryParse('$value') ?? 0;
  String _message(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      if (data['detail'] is String) return data['detail'] as String;
      if (data.isNotEmpty) return data.values.first.toString();
    }
    if (error.type == DioExceptionType.connectionError || error.type == DioExceptionType.connectionTimeout) return 'Cannot connect to the BuildPro server.';
    return fallback;
  }
}
