import 'package:client/data/models/product_tracking.dart';
import 'package:flutter/material.dart';

class PosSaleQuantityDialog extends StatefulWidget {
  const PosSaleQuantityDialog({super.key, required this.product});

  final ProductTrackingConfiguration product;

  @override
  State<PosSaleQuantityDialog> createState() => _PosSaleQuantityDialogState();
}

class _PosSaleQuantityDialogState extends State<PosSaleQuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '1');
  late String _unit = widget.product.allowedSaleUnits.first;

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
                Text(
                  '${widget.product.totalBaseQuantity.toStringAsFixed(2)} ${widget.product.baseUnit} currently available',
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantity,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                        ),
                        validator: (value) {
                          final number = double.tryParse(value ?? '');
                          if (number == null || number <= 0) {
                            return 'Enter a valid quantity';
                          }
                          if (!widget.product.allowFractional &&
                              number != number.roundToDouble()) {
                            return 'Whole numbers only';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: widget.product.allowedSaleUnits
                            .map(
                              (unit) => DropdownMenuItem(
                                value: unit,
                                child: Text(unit),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _unit = value!),
                      ),
                    ),
                  ],
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
            Navigator.pop(context, (
              quantity: double.parse(_quantity.text),
              unit: _unit,
            ));
          },
          child: const Text('Add to cart'),
        ),
      ],
    );
  }
}
