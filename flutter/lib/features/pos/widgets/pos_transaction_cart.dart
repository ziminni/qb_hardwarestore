import 'package:client/core/constants/app_colors.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_utang_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PosTransactionCart extends StatelessWidget {
  const PosTransactionCart({
    super.key,
    required this.onPayment,
    required this.onClear,
    required this.onChangeCustomer,
    this.onHold,
  });

  final VoidCallback onPayment;
  final VoidCallback onClear;

  /// Parks the basket without taking money (Phase 3 held sale).
  ///
  /// Optional because the cart is built by tests and screens with no held-cart
  /// queue behind them; when null the action is absent rather than shown dead.
  final VoidCallback? onHold;

  /// Opens the customer picker. The sale's account is [PosTransactionViewmodel]
  /// state, so this row only reports the selection and asks to change it.
  final VoidCallback onChangeCustomer;

  /// Below this height the cart scrolls as a whole (see [build]).
  static const double _roomyHeight = 520;

  static const _edge = EdgeInsets.symmetric(horizontal: 18);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PosTransactionViewmodel>();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A short window cannot fit the header, the lines AND the buttons,
            // so the whole cart scrolls as one instead of overflowing.
            final roomy = constraints.maxHeight >= _roomyHeight;
            final content = _content(context, state, roomy);
            return roomy ? content : SingleChildScrollView(child: content);
          },
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    PosTransactionViewmodel state,
    bool roomy,
  ) {
    final lines = state.lines.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 40, horizontal: 18),
            child: Center(
              child: Text(
                'Select a product to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        : _lines(context, state, scrolls: roomy);
    return Column(
      mainAxisSize: roomy ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, state),
        if (roomy) Expanded(child: lines) else lines,
        _footer(context, state),
      ],
    );
  }

  Widget _header(BuildContext context, PosTransactionViewmodel state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Current sale',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: 'Cinzel',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${state.itemCount} line item(s)',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Decision 14: who is paying sits above what they are paying for, so the cashier
          // sees the account before assembling the basket. An anonymous sale is marked as
          // such, because that is the difference between "paid in full" and "becomes a
          // debt" - and a walk-in CANNOT owe.
          Material(
            color: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: onChangeCustomer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CUSTOMER',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            state.customerLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: state.selectedCustomer == null
                                  ? AppColors.textSecondary
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6E5A22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Decision 14: the balance sits with the account, at the till, because a credit
          // limit is only weighable where the sale is being decided.
          PosUtangPanel(
            customer: state.selectedCustomer,
            summary: state.ledgerSummary,
            error: state.ledgerError,
            isLoading: state.isLoadingLedger,
            thisSaleTotal: state.total,
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, PosTransactionViewmodel state) {
    const tabular = [FontFeature.tabularFigures()];
    final total = '₱${state.total.toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFDF7),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Subtotal',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              Text(
                '₱${state.subtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  total,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabular,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // The one action the till exists for: the biggest target on screen.
          FilledButton.icon(
            onPressed: state.lines.isEmpty ? null : onPayment,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Proceed to payment'),
          ),
          const SizedBox(height: 10),
          // Decision 03: a cashier must be able to park a half-rung basket when
          // the customer walks away. Disabled on an empty cart for the same
          // reason Pay is: a hold with no lines leaves a row that resumes to
          // nothing.
          Row(
            children: [
              if (onHold != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: state.lines.isEmpty ? null : onHold,
                    style: _secondary,
                    child: const Text(
                      'Hold transaction',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed: state.lines.isEmpty ? null : onClear,
                  style: _secondary.copyWith(
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? null
                          : AppColors.errorText,
                    ),
                  ),
                  child: const Text(
                    'Clear transaction',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static final ButtonStyle _secondary = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    backgroundColor: AppColors.cardBackground,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget _lines(
    BuildContext context,
    PosTransactionViewmodel state, {
    required bool scrolls,
  }) {
    return ListView.separated(
      shrinkWrap: !scrolls,
      physics: scrolls ? null : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: state.lines.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 18, endIndent: 18),
      itemBuilder: (context, index) {
        final line = state.lines[index];
        // Decision 06 section 3: a short-stock rejection is recoverable
        // in place, so the cart names the row the cashier must fix.
        // Without this the viewmodel's marker would be a fact nothing
        // shows - the same defect the final review found, one layer up.
        final isShort = line.variantUomId == state.insufficientStockLineId;
        final scheme = Theme.of(context).colorScheme;
        final quantity = line.quantity == line.quantity.roundToDouble()
            ? line.quantity.toStringAsFixed(0)
            : line.quantity.toStringAsFixed(2);

        void step(int delta) {
          final error = state.stepLine(index, delta);
          if (error != null) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(error)));
          }
        }

        return Container(
          key: ValueKey('pos-cart-line-$index'),
          color: isShort ? scheme.errorContainer : null,
          padding: _edge.add(const EdgeInsets.symmetric(vertical: 12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.productName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${line.variantName} · '
                          '₱${line.unitPrice.toStringAsFixed(2)} per '
                          '${line.unit.toLowerCase()}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isShort
                                ? scheme.onErrorContainer
                                : AppColors.textSecondary,
                          ),
                        ),
                        if (isShort)
                          Text(
                            'Not enough stock. Reduce this line.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onErrorContainer,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '₱${line.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Stepper(
                    quantity: quantity,
                    unit: line.unit.toLowerCase(),
                    productName: line.productName,
                    onMinus: () => step(-1),
                    onPlus: () => step(1),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => state.removeLine(index),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.errorText,
                      minimumSize: const Size(0, 40),
                    ),
                    child: Text(
                      'Remove',
                      semanticsLabel: 'Remove ${line.productName}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.unit,
    required this.productName,
    required this.onMinus,
    required this.onPlus,
  });

  final String quantity;
  final String unit;
  final String productName;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback onTap) {
      return SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 18,
          onPressed: onTap,
          icon: Icon(icon),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove, 'One fewer $productName', onMinus),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: Text(
              '$quantity $unit',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          button(Icons.add, 'One more $productName', onPlus),
        ],
      ),
    );
  }
}
