import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/supplier.dart';
import 'package:flutter/material.dart';

class PurchasesFormDialog extends StatefulWidget {
  const PurchasesFormDialog({
    super.key,
    required this.suppliers,
    required this.products,
  });
  final List<Supplier> suppliers;
  final List<Product> products;
  @override
  State<PurchasesFormDialog> createState() => _PurchasesFormDialogState();
}

class _PurchasesFormDialogState extends State<PurchasesFormDialog> {
  final _key = GlobalKey<FormState>();
  late int _supplierId = widget.suppliers.first.id;
  late int _variantId = widget.products.first.variants.first.id;
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final variants = [
      for (final product in widget.products)
        for (final variant in product.variants)
          (product: product, variant: variant),
    ];
    return AlertDialog(
      title: const Text('Create Purchase Order'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _key,
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _supplierId,
                  decoration: const InputDecoration(labelText: 'Supplier'),
                  items: widget.suppliers
                      .where((item) => item.isActive)
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.companyName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _supplierId = value ?? _supplierId),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<int>(
                  initialValue: _variantId,
                  decoration: const InputDecoration(
                    labelText: 'Product Variant',
                  ),
                  items: variants
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.variant.id,
                          child: Text(
                            '${item.product.baseName} — ${item.variant.variantName}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _variantId = value ?? _variantId),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Order Quantity',
                  ),
                  validator: (value) => (double.tryParse(value ?? '') ?? 0) <= 0
                      ? 'Enter a quantity greater than zero.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
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
            final supplier = widget.suppliers.firstWhere(
              (item) => item.id == _supplierId,
            );
            final record = variants.firstWhere(
              (item) => item.variant.id == _variantId,
            );
            Navigator.pop(
              context,
              PurchaseOrder(
                id: 0,
                supplierId: supplier.id,
                supplierName: supplier.companyName,
                orderDate: DateTime.now(),
                expectedDelivery: DateTime.now().add(const Duration(days: 7)),
                status: PurchaseStatus.draft,
                createdBy: 'Inventory Staff',
                notes: _notes.text.trim(),
                items: [
                  PurchaseItem(
                    productName: record.product.baseName,
                    variantName: record.variant.variantName,
                    sku: record.variant.sku,
                    quantity: double.parse(_quantity.text),
                    receivedQuantity: 0,
                    unitCost: record.variant.costPrice,
                  ),
                ],
              ),
            );
          },
          child: const Text('Create Draft'),
        ),
      ],
    );
  }
}
