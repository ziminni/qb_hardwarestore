// Phase 5 Task 3: the Store Manager's correction without an original sale.
//
// Same wire shape as the till's linked return minus `original_transaction` —
// the server treats an absent key as unlinked, prices lines at the selling
// units' `default_selling_price`, and 403s non-managers itself. The customer
// is chosen here because there is no original sale to inherit one from, and
// the selling unit comes from the live catalogue (never a typed id): the
// dialog cannot offer what the server does not sell.

import 'package:client/data/models/customer.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/returns_service.dart';
import 'package:flutter/material.dart';

/// One row the dialog posts: a selling unit id plus the quantity coming back.
class _ReturnLine {
  _ReturnLine({required this.variantUomId, required this.qty});

  int? variantUomId;
  double qty;
}

/// Flat selling-unit option: "Product Variant (UOM) — ₱price".
class _UnitOption {
  const _UnitOption({
    required this.id,
    required this.label,
    required this.price,
  });

  final int id;
  final String label;
  final double price;
}

List<_UnitOption> _unitOptions(List<Product> products) => [
  for (final product in products)
    for (final variant in product.variants)
      for (final uom in variant.sellingUoms)
        _UnitOption(
          id: uom.id,
          label: '${product.baseName} ${variant.variantName} (${uom.uomCode})',
          price: uom.defaultSellingPrice,
        ),
];

class UnlinkedReturnDialog extends StatefulWidget {
  const UnlinkedReturnDialog({
    super.key,
    required this.returnsService,
    required this.customerService,
    required this.productsService,
    required this.onPosted,
  });

  final ReturnsService returnsService;
  final CustomerService customerService;
  final ProductsService productsService;

  /// Reloads the returns list after a posted return.
  final VoidCallback onPosted;

  @override
  State<UnlinkedReturnDialog> createState() => _UnlinkedReturnDialogState();
}

class _UnlinkedReturnDialogState extends State<UnlinkedReturnDialog> {
  bool _loading = true;
  String? _loadError;
  List<Customer> _customers = const [];
  List<_UnitOption> _units = const [];

  int? _customerId;
  final List<_ReturnLine> _lines = [_ReturnLine(variantUomId: null, qty: 1)];
  final _reason = TextEditingController();
  TenderMethod _method = TenderMethod.cash;
  String? _error;
  bool _posting = false;
  ReturnResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.customerService.fetchCustomers(),
        widget.productsService.fetchCatalogue(),
      ]);
      if (!mounted) return;
      final units = _unitOptions(
        (results[1] as ProductsSnapshot).products
            .where((p) => p.isActive)
            .toList(),
      );
      setState(() {
        _customers = results[0] as List<Customer>;
        _units = units;
        if (_units.isNotEmpty) _lines.single.variantUomId = _units.first.id;
        _loading = false;
      });
    } on CustomerServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } on ProductsServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  double get _linesTotal {
    final prices = {for (final u in _units) u.id: u.price};
    return _lines.fold<double>(
      0,
      (sum, line) =>
          sum +
          (prices[line.variantUomId] ?? 0) * (line.qty.isNaN ? 0 : line.qty),
    );
  }

  Future<void> _post() async {
    final customerId = _customerId;
    final reason = _reason.text.trim();
    final lines = [
      for (final line in _lines)
        if (line.variantUomId != null && line.qty > 0)
          ReturnRequestLine(variantUomId: line.variantUomId!, qty: line.qty),
    ];
    if (customerId == null) {
      setState(() => _error = 'Choose the customer this refund goes to.');
      return;
    }
    if (lines.isEmpty) {
      setState(
        () => _error = 'Add at least one line with a quantity above zero.',
      );
      return;
    }
    if (reason.isEmpty) {
      setState(
        () => _error = 'A reason is required — every refund explains itself.',
      );
      return;
    }
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      final result = await widget.returnsService.postUnlinkedReturn(
        customerId: customerId,
        reason: reason,
        paymentMethod: _method.code,
        lines: lines,
      );
      if (!mounted) return;
      setState(() {
        _posting = false;
        _result = result;
      });
      widget.onPosted();
    } on ReturnsServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unlinked return'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _loadError != null
              ? Text(_loadError!)
              : _result != null
              ? _summary(_result!)
              : _form(),
        ),
      ),
      actions: [
        if (_result == null) ...[
          TextButton(
            onPressed: _posting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _posting ? null : _post,
            child: _posting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Post return'),
          ),
        ] else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
      ],
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'No original sale: the refund settles this customer\u2019s oldest '
          'open debt first, and only the excess leaves the drawer.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _customerId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Customer'),
          items: [
            for (final customer in _customers)
              DropdownMenuItem(
                value: customer.id,
                child: Text(customer.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => setState(() => _customerId = value),
        ),
        const SizedBox(height: 12),
        ..._lines.asMap().entries.map((indexed) {
          final index = indexed.key;
          final line = indexed.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    initialValue: line.variantUomId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Selling unit',
                    ),
                    items: [
                      for (final unit in _units)
                        DropdownMenuItem(
                          value: unit.id,
                          child: Text(
                            '${unit.label} — ₱${unit.price.toStringAsFixed(2)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => line.variantUomId = value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: line.qty.toStringAsFixed(
                      line.qty == line.qty.round() ? 0 : 2,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Qty'),
                    onChanged: (value) =>
                        line.qty = double.tryParse(value) ?? 0,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove line',
                  onPressed: _lines.length == 1
                      ? null
                      : () => setState(() => _lines.removeAt(index)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(
              () => _lines.add(
                _ReturnLine(
                  variantUomId: _units.isEmpty ? null : _units.first.id,
                  qty: 1,
                ),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add line'),
          ),
        ),
        Text(
          'Estimated value ₱${_linesTotal.toStringAsFixed(2)} at current prices — '
          'the server reprices at posting.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          decoration: const InputDecoration(
            labelText: 'Reason for the return (required)',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TenderMethod>(
          initialValue: _method,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Refund method'),
          items: [
            for (final method in TenderMethod.refundTenders)
              DropdownMenuItem(value: method, child: Text(method.label)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _method = value);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _summary(ReturnResult result) {
    final refund = result.refund;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Return posted: ${result.returnNo}'),
        const SizedBox(height: 8),
        Text(
          'Return value ₱${refund.returnValue.toStringAsFixed(2)} · debt reduced '
          '₱${refund.debtReduced.toStringAsFixed(2)} · cash refunded '
          '₱${refund.cashRefund.toStringAsFixed(2)}.',
        ),
      ],
    );
  }
}
