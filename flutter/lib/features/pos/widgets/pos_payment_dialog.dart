import 'package:flutter/material.dart';

class PosPaymentDetails {
  const PosPaymentDetails(this.method, this.amountPaid);
  final String method;
  final double amountPaid;
}

class PosPaymentDialog extends StatefulWidget {
  const PosPaymentDialog({super.key, required this.total});
  final double total;

  @override
  State<PosPaymentDialog> createState() => _PosPaymentDialogState();
}

class _PosPaymentDialogState extends State<PosPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
    text: widget.total.toStringAsFixed(2),
  );
  String _method = 'Cash';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paid = double.tryParse(_amount.text) ?? 0;
    return AlertDialog(
      title: const Text('Payment'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Amount due: ₱${widget.total.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: const ['Cash', 'GCash', 'Card']
                      .map(
                        (method) => DropdownMenuItem(
                          value: method,
                          child: Text(method),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _method = value!;
                    if (_method != 'Cash') {
                      _amount.text = widget.total.toStringAsFixed(2);
                    }
                  }),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amount,
                  enabled: _method == 'Cash',
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount received',
                  ),
                  // #21 (2026-10-17): this validator used to reject any amount below the total,
                  // which made `payment.amountPaid < transaction.total` in _pay unreachable - and
                  // with it decision 06 section 4, Phase 4 T6's three-way walk-in flow, and the
                  // server's WALK_IN_CANNOT_OWE guard. A short amount is a real transaction: it
                  // records an utang. So the field accepts it and the WARNING below does the work
                  // the error used to do, because a validator error would block the submission the
                  // cashier actually intends.
                  validator: (value) {
                    if (double.tryParse(value ?? '') == null) {
                      return 'Enter a valid amount';
                    }
                    return null;
                  },
                ),
                if (paid < widget.total)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '\u20b1${(widget.total - paid).toStringAsFixed(2)} will be left unpaid \u2014 this records an utang',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  'Change: ₱${(paid - widget.total).clamp(0, double.infinity).toStringAsFixed(2)}',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Simulation only. No real payment will be processed.',
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
              PosPaymentDetails(_method, double.parse(_amount.text)),
            );
          },
          child: const Text('Complete sale'),
        ),
      ],
    );
  }
}
