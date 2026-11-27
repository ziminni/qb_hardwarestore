import 'package:client/shared/widgets/operational_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('coverage and FIFO charts render narrow without hiding values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                StockCoverageChart(
                  items: [
                    StockCoverageItem('Cement', 5, 10),
                    StockCoverageItem('Pipe', 0, 3),
                  ],
                ),
                FifoAgeChart(items: [FifoAgeItem('Cement batch', 2, 4, 6)]),
                SignedVarianceChart(
                  title: 'Stock adjustment',
                  subtitle: 'Direction',
                  items: [
                    SignedVarianceItem('Return', -2),
                    SignedVarianceItem('Correction', 3),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('50% of minimum'), findsOneWidget);
    expect(find.text('0% of minimum'), findsOneWidget);
    expect(find.textContaining('Old 6'), findsOneWidget);
    expect(find.text('Decrease'), findsOneWidget);
    expect(find.text('Increase'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
