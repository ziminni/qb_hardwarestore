import 'package:client/data/models/pos_transaction.dart';
import 'package:flutter/material.dart';

class PosSaleSelection {
  const PosSaleSelection({required this.item, required this.quantity});
  final PosCatalogItem item;
  final double quantity;
}

class PosSaleQuantityDialog extends StatefulWidget {
  const PosSaleQuantityDialog({
    super.key,
    required this.product,
    required this.options,
  });

  final PosCatalogItem product;
  final List<PosCatalogItem> options;

  @override
  State<PosSaleQuantityDialog> createState() => _PosSaleQuantityDialogState();
}

class _PosSaleQuantityDialogState extends State<PosSaleQuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '1');
  late PosCatalogItem _selected = widget.options.first;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add ${widget.product.productName}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.product.variantName),
                const SizedBox(height: 18),
                DropdownButtonFormField<PosCatalogItem>(
                  isExpanded: true,
                  initialValue: _selected,
                  decoration: const InputDecoration(labelText: 'Selling unit'),
                  items: widget.options
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            '${item.unit} — ₱${item.unitPrice.toStringAsFixed(2)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _selected = value);
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  '${_selected.availableSaleQuantity.toStringAsFixed(2)} ${_selected.unit} currently available',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _quantity,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    suffixText: _selected.unit,
                  ),
                  validator: (value) {
                    final number = double.tryParse(value ?? '');
                    if (number == null || number <= 0) {
                      return 'Enter a valid quantity';
                    }
                    const wholeUnits = {
                      'piece',
                      'bag',
                      'box',
                      'sheet',
                      'roll',
                      'pack',
                    };
                    if (wholeUnits.contains(_selected.unit.toLowerCase()) &&
                        number != number.roundToDouble()) {
                      return 'Use a whole number for ${_selected.unit}';
                    }
                    if (number > _selected.availableSaleQuantity) {
                      return 'Only ${_selected.availableSaleQuantity.toStringAsFixed(2)} available';
                    }
                    return null;
                  },
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
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              PosSaleSelection(
                item: _selected,
                quantity: double.parse(_quantity.text),
              ),
            );
          },
          child: const Text('Add to cart'),
        ),
      ],
    );
  }
}
