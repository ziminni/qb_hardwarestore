import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The sale in one line, pinned under the products on a narrow window: how
/// many lines, the total, the way into the full cart, and Pay.
class PosCartBar extends StatelessWidget {
  const PosCartBar({
    super.key,
    required this.onViewCart,
    required this.onPayment,
  });

  final VoidCallback onViewCart;
  final VoidCallback onPayment;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PosTransactionViewmodel>();
    final empty = state.lines.isEmpty;
    return Material(
      color: AppColors.brandBlack,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${state.itemCount} line item(s)',
                    style: const TextStyle(
                      color: Color(0xFFD9D3C4),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    formatPeso(state.total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.brandWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (state.hasCreditMarkup) ...[
              PosCreditPriceToggle(onDark: true),
              const SizedBox(width: AppSpacing.sm),
            ],
            PosOfficialReceiptToggle(onDark: true),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton(
              onPressed: onViewCart,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandWhite,
                side: const BorderSide(color: Color(0xFF5A554C)),
                minimumSize: const Size(0, 48),
              ),
              child: const Text('View cart'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: empty ? null : onPayment,
              // The default disabled grey vanishes on the black bar; an empty
              // cart's Pay must still read as a (greyed) button.
              style: FilledButton.styleFrom(
                minimumSize: const Size(88, 48),
                disabledBackgroundColor: const Color(0xFF3A362F),
                disabledForegroundColor: const Color(0xFFA9A396),
              ),
              child: const Text('Pay'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Utang prices" switch (owner ruling): the ONE place a credit sale is
/// chosen, and it is chosen BEFORE the tender is taken.
///
/// * Off (the default) the till charges the shelf price. Once any unit carries a
///   configured markup and the sale is underpaid, the server refuses that
///   combination (`CREDIT_PRICE_REQUIRED`), so the switch is what the cashier
///   flips first - not something inferred from a payment after the fact.
/// * On, EVERY marked-up line is charged at its credit price, even when part of
///   the bill is paid in cash/GCash. Order lines keep their agreed price.
/// * A credit sale that ends fully paid is refused by the server, so it can
///   never quietly ring a paid sale at credit prices.
///
/// Rendered only when the cart actually holds a marked-up unit: offering a
/// switch that changes nothing would be a control with no effect.
class PosCreditPriceToggle extends StatelessWidget {
  const PosCreditPriceToggle({super.key, this.onDark = false});

  /// The pinned bar sits on the brand black, the cart on the page background.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PosTransactionViewmodel>();
    final color = onDark ? AppColors.brandWhite : AppColors.textPrimary;
    return Tooltip(
      message:
          'Credit prices cover all items with markup, even if part is paid now. '
          'A fully paid sale cannot be a credit sale.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            key: const ValueKey('credit-sale-switch'),
            value: state.creditSale,
            onChanged: state.lines.isEmpty ? null : state.setCreditSale,
          ),
          Text('Utang prices', style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}

/// The till's "customer wants an Official Receipt (BIR)" switch, and the field
/// its Invoice number is typed into (store-ops Phase 1).
///
/// The shop prints an Order Slip for every sale; the BIR Official Receipt is a
/// separate PAPER booklet. When the customer asks for one the cashier writes it
/// out by hand and types its Invoice number here, so the sale is tagged and can
/// be reprinted later with `OR Invoice No.` under the OS number.
class PosOfficialReceiptToggle extends StatefulWidget {
  const PosOfficialReceiptToggle({super.key, this.onDark = false});

  /// The pinned bar sits on the brand black, the cart on the page background.
  final bool onDark;

  static const switchKey = ValueKey('official-receipt-switch');
  static const fieldKey = ValueKey('official-receipt-invoice-field');

  @override
  State<PosOfficialReceiptToggle> createState() =>
      _PosOfficialReceiptToggleState();
}

class _PosOfficialReceiptToggleState extends State<PosOfficialReceiptToggle> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setEnabled(bool value) {
    final vm = context.read<PosTransactionViewmodel>();
    vm.setAttachOrEnabled(value);
    if (!value) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PosTransactionViewmodel>();
    final enabled = state.attachOrEnabled || state.invoiceNo != null;
    if (!enabled && _controller.text.isNotEmpty) {
      _controller.clear();
    } else if (state.invoiceNo != null &&
        _controller.text.trim() != state.invoiceNo) {
      _controller.value = TextEditingValue(
        text: state.invoiceNo!,
        selection: TextSelection.collapsed(offset: state.invoiceNo!.length),
      );
    }

    final color = widget.onDark ? AppColors.brandWhite : AppColors.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message:
              'Customer wants an Official Receipt (OR). Write the paper OR, '
              'then type its OR / Invoice number.',
          child: Switch(
            key: PosOfficialReceiptToggle.switchKey,
            value: enabled,
            onChanged: _setEnabled,
          ),
        ),
        Text('Attach OR?', style: TextStyle(color: color, fontSize: 13)),
        if (enabled) ...[
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 150,
            child: TextField(
              key: PosOfficialReceiptToggle.fieldKey,
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: context.read<PosTransactionViewmodel>().setInvoiceNo,
              style: TextStyle(color: color, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'OR / Invoice no.',
                labelStyle: TextStyle(color: color, fontSize: 12),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
