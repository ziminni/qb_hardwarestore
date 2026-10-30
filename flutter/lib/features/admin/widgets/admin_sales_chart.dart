import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:flutter/material.dart';

class AdminSalesChart extends StatelessWidget {
  const AdminSalesChart({
    super.key,
    required this.values,
    required this.labels,
  });

  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final maximum = values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 280,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (index) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: values[index] / maximum,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
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
                  const SizedBox(height: 8),
                  Text(labels[index], style: AppTextStyles.labelSmall),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
