import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:flutter/material.dart';

/// One amount of one item, as the summary says it: "3 BAG Portland Cement 40kg".
typedef ReleaseAmount = ({String name, double qty, String unit});

String _say(ReleaseAmount line) => [
  formatQuantity(line.qty),
  if (line.unit.isNotEmpty) line.unit,
  line.name,
].join(' ');

/// What today's release gives and what stays open for the next visit, said
/// before the irreversible press (2026-11-27 design). The peso figure is the
/// screen's estimate from unit prices; the receipt shows the server's total.
class ReleaseSummaryBar extends StatelessWidget {
  const ReleaseSummaryBar({
    super.key,
    required this.giving,
    required this.total,
    required this.stillOpen,
  });

  final List<ReleaseAmount> giving;
  final double total;
  final List<ReleaseAmount> stillOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('release-summary'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            giving.isEmpty
                ? 'Giving today: nothing yet'
                : 'Giving today: ${giving.map(_say).join(', ')} · '
                      '${formatPeso(total)} on account',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            stillOpen.isEmpty
                ? 'Nothing stays open: this finishes the request.'
                : 'Still open after this: ${stillOpen.map(_say).join(', ')}. '
                      'The same slip works next visit.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
