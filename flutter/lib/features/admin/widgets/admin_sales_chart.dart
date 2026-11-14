import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:flutter/material.dart';

class AdminSalesChart extends StatelessWidget {
  const AdminSalesChart({
    super.key,
    required this.values,
    required this.labels,
  });

  final List<double> values;
  final List<String> labels;

  /// Breathing room a label needs on each side of its text so two neighbouring
  /// labels never touch.
  static const double _labelPadding = 8;

  /// Space between two bars.
  static const double _barGap = 8;

  /// The widest a single bar gets, however much room its slot has.
  static const double _maxBarWidth = 56;

  /// The axis text, fixed here so the width it is measured at is the width it
  /// is painted at: an inherited style plus a different size paints labels
  /// wider than the room they were thinned for.
  static const TextStyle _labelStyle = TextStyle(
    fontSize: 11,
    color: AppColors.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    final maximum = values.reduce((a, b) => a > b ? a : b);
    // A zero-gross week makes maximum 0 (0/0 = NaN) and a refund-heavy day
    // goes negative: both violate FractionallySizedBox's heightFactor >= 0
    // and red-screen the tab. Zero range renders flat; negatives clamp to it.
    final double range = maximum <= 0 ? 1.0 : maximum;
    return SizedBox(
      height: 280,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 0.0;
          // A label is as wide as its text and sits centred under its bar, so
          // the first and last bar are inset by half a label: otherwise the
          // newest date hangs over the panel border.
          final widest = _widestLabel(context);
          final inset = math.min(widest / 2, width / 4);
          final slot = (width - inset * 2) / math.max(values.length, 1);
          // A 30 day month in a 760 px window leaves 25 px per bar, and a date
          // needs about four times that: painting every label printed them on
          // top of each other. Thin them to as many as fit, measured in the
          // style the labels are painted with rather than a guessed number.
          final every = slot <= 0
              ? 1
              : math.max(1, ((widest + _labelPadding) / slot).ceil());
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(values.length, (index) {
                // Counted back from the newest bar, so the latest day is always
                // named even when the older labels are thinned out.
                final labelled = (values.length - 1 - index) % every == 0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _barGap),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: SizedBox(
                              // A bar keeps a chart's width when its slot grows:
                              // seven bars across 1440 px would be 120 px slabs.
                              width: math.min(
                                math.max(slot - 2 * _barGap, 0),
                                _maxBarWidth,
                              ),
                              child: FractionallySizedBox(
                                // Without a width factor the bar gets LOOSE width
                                // and a box with no child collapses to zero: the
                                // chart painted labels over nothing.
                                widthFactor: 1,
                                heightFactor: (values[index] / range).clamp(
                                  0.0,
                                  1.0,
                                ),
                                child: Container(
                                  key: ValueKey('admin-sales-chart-bar-$index'),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        AppColors.brandGoldLight,
                                        AppColors.brandGold,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(AppRadii.small),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _label(
                          index < labels.length ? labels[index] : null,
                          labelled,
                          slot,
                          every,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  /// The widest label at the size it is painted, so the axis can thin itself
  /// without guessing how much room a date takes. Merged onto the ambient style
  /// because that is what a `Text` paints with: measuring the bare style would
  /// drop the font family and overstate every label.
  double _widestLabel(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(_labelStyle);
    final painter = TextPainter(textDirection: TextDirection.ltr);
    var widest = 0.0;
    for (final label in labels) {
      painter.text = TextSpan(text: label, style: style);
      painter.layout();
      widest = math.max(widest, painter.width);
    }
    painter.dispose();
    return widest;
  }

  /// A label cell that keeps the bar column's width, but lets a thinned label
  /// use the room of the bars it stands in for instead of wrapping "Oct 19"
  /// onto two lines.
  Widget _label(String? text, bool labelled, double slot, int every) {
    return SizedBox(
      width: slot,
      height: 18,
      child: !labelled || text == null
          ? null
          : OverflowBox(
              // Zero min width: the cell is wider than its own bar column, and
              // a min above the max throws during layout.
              minWidth: 0,
              maxWidth: slot * every,
              child: Text(
                text,
                style: _labelStyle,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
              ),
            ),
    );
  }
}
