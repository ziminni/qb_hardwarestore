import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The blue of "goes out today" on the progress bar and the stepper.
const Color releaseGiveNowColor = Color(0xFF2563EB);

/// One line of a request at the release counter (2026-11-27 design).
///
/// Says in words what earlier visits gave, what is still owed and what can go out
/// now; the bar shows the same (grey = given, blue = Give now). A line that can go
/// carries a Give now stepper; [onChanged] is null for every other line.
class ReleaseLineRow extends StatelessWidget {
  const ReleaseLineRow({
    super.key,
    required this.item,
    required this.giveNow,
    required this.changed,
    this.onChanged,
    this.last = false,
  });

  final VerifiedRequisitionItem item;
  final double giveNow;

  /// True when the cashier moved Give now away from what can go out.
  final bool changed;
  final ValueChanged<double>? onChanged;
  final bool last;

  String get _unit => item.unit.isEmpty ? '' : ' ${item.unit}';

  String get _owedLine {
    if (item.available == false) return '${formatQuantity(item.remaining)} not served';
    if (item.availability == LineAvailability.done || item.remaining <= 0) {
      return 'Everything was given';
    }
    final owed = '${formatQuantity(item.remaining)} still to give';
    return item.isReleasable
        ? '$owed · up to ${formatQuantity(item.releasable)} can go out now'
        : '$owed · none can go out now';
  }

  @override
  Widget build(BuildContext context) {
    final refused = item.available == false;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
      child: Opacity(
        opacity: refused ? 0.7 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.variantName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatQuantity(item.given)} of '
                    '${formatQuantity(item.quantity)}$_unit given',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _ProgressBar(
                    given: item.given,
                    now: refused ? 0 : giveNow,
                    total: item.quantity,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _owedLine,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(
              width: 220,
              child: onChanged == null
                  ? const Text(
                      '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GiveNowStepper(
                          item: item,
                          value: giveNow,
                          onChanged: onChanged!,
                        ),
                        if (changed)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'changed from ${formatQuantity(item.releasable)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(width: 168, child: _StatusCell(item: item)),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.given,
    required this.now,
    required this.total,
  });

  final double given;
  final double now;
  final double total;

  @override
  Widget build(BuildContext context) {
    double share(double part) =>
        total <= 0 ? 0 : (part / total).clamp(0.0, 1.0).toDouble();
    final givenShare = share(given);
    final nowShare = share(now).clamp(0.0, 1 - givenShare).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: LayoutBuilder(
          builder: (context, constraints) => Container(
            color: AppColors.border,
            child: Row(
              children: [
                Container(
                  width: constraints.maxWidth * givenShare,
                  color: AppColors.textSecondary,
                ),
                Container(
                  width: constraints.maxWidth * nowShare,
                  color: releaseGiveNowColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// − [amount] + with the unit beside it. Typing is allowed: whole units take
/// digits only, measured units up to 2 decimals. The viewmodel clamps; the field
/// shows the clamped value back.
class _GiveNowStepper extends StatefulWidget {
  const _GiveNowStepper({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  final VerifiedRequisitionItem item;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_GiveNowStepper> createState() => _GiveNowStepperState();
}

class _GiveNowStepperState extends State<_GiveNowStepper> {
  late final TextEditingController _text = TextEditingController(
    text: formatQuantity(widget.value),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _show(widget.value);
    });
  }

  @override
  void didUpdateWidget(covariant _GiveNowStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    final typed = double.tryParse(_text.text.replaceAll(',', ''));
    // Rewrite the field only when it disagrees with the amount, so typing "2."
    // is not interrupted; an empty field waits for the cashier to finish.
    if (typed == null ? !_focus.hasFocus : (typed - widget.value).abs() > 1e-9) {
      _show(widget.value);
    }
  }

  void _show(double value) {
    final text = formatQuantity(value);
    if (_text.text == text) return;
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.item.id;
    final value = widget.value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          key: ValueKey('give-now-minus-$id'),
          icon: Icons.remove,
          tooltip: 'One less',
          onPressed: value <= 0 ? null : () => widget.onChanged(value - 1),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 72,
          child: TextField(
            key: ValueKey('give-now-$id'),
            controller: _text,
            focusNode: _focus,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(
              decimal: !widget.item.isWhole,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                widget.item.isWhole
                    ? RegExp(r'^\d*')
                    : RegExp(r'^\d*\.?\d{0,2}'),
              ),
            ],
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.medium),
                borderSide: const BorderSide(
                  color: releaseGiveNowColor,
                  width: 2,
                ),
              ),
            ),
            onChanged: (raw) {
              final typed = double.tryParse(raw);
              if (typed != null) widget.onChanged(typed);
            },
          ),
        ),
        const SizedBox(width: 6),
        _StepButton(
          key: ValueKey('give-now-plus-$id'),
          icon: Icons.add,
          tooltip: 'One more',
          onPressed: value >= widget.item.releasable
              ? null
              : () => widget.onChanged(value + 1),
        ),
        if (widget.item.unit.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.item.unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 36,
      child: IconButton.outlined(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(icon),
      ),
    );
  }
}

/// The line's status pill, plus the store's reason for a refused line.
class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.item});

  final VerifiedRequisitionItem item;

  @override
  Widget build(BuildContext context) {
    // Decision 13: the store's answer outranks the shelf's word.
    if (item.available == false) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const StatusBadge(label: 'Not available', tone: StatusTone.error),
          if (item.declineReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.declineReason,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      );
    }
    final (label, tone) = switch (item.availability) {
      LineAvailability.full => ('Enough stock', StatusTone.success),
      LineAvailability.short => (
        'Short: up to ${formatQuantity(item.releasable)} now',
        StatusTone.warning,
      ),
      LineAvailability.unavailable => ('Out of stock', StatusTone.error),
      LineAvailability.done => ('Already given', StatusTone.neutral),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusBadge(label: label, tone: tone),
    );
  }
}
