import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/sales.dart';
import 'package:flutter/material.dart';

class InventoryReturnFormDialog extends StatefulWidget {
  const InventoryReturnFormDialog({super.key, required this.sales});
  final List<InventorySale> sales;
  @override
  State<InventoryReturnFormDialog> createState() =>
      _InventoryReturnFormDialogState();
}

class _InventoryReturnFormDialogState extends State<InventoryReturnFormDialog> {
  final _key = GlobalKey<FormState>();
  late InventorySale _sale = widget.sales.first;
  late InventorySaleLine _line = _sale.lines.first;
  final _quantity = TextEditingController(text: '1');
  final _reason = TextEditingController();
  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record Customer Return'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            children: [
              DropdownButtonFormField<InventorySale>(
                initialValue: _sale,
                decoration: const InputDecoration(
                  labelText: 'Sales Transaction',
                ),
                items: widget.sales
                    .map(
                      (sale) => DropdownMenuItem(
                        value: sale,
                        child: Text('${sale.transactionNo} — ${sale.customer}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _sale = value ?? _sale;
                  _line = _sale.lines.first;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<InventorySaleLine>(
                key: ValueKey(_sale.transactionNo),
                initialValue: _line,
                decoration: const InputDecoration(labelText: 'Returned Item'),
                items: _sale.lines
                    .map(
                      (line) => DropdownMenuItem(
                        value: line,
                        child: Text(
                          '${line.productName} — ${line.variantName}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _line = value ?? _line),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
                validator: (value) => (double.tryParse(value ?? '') ?? 0) <= 0
                    ? 'Enter a quantity greater than zero.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _reason,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a return reason.'
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          Navigator.pop(
            context,
            InventoryReturn(
              reference:
                  'RET-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
              date: DateTime.now(),
              type: InventoryReturnType.customer,
              relatedReference: _sale.transactionNo,
              productName: _line.productName,
              variantName: _line.variantName,
              sku: _line.sku,
              quantity: double.parse(_quantity.text),
              reason: _reason.text.trim(),
              status: InventoryReturnStatus.pending,
              processedBy: 'Inventory Staff',
            ),
          );
        },
        child: const Text('Record Return'),
      ),
    ],
  );
}
