// A report card is drawn only for accounts the server lets read it, so a stock
// manager never opens "You do not have access to reports".

import 'package:client/core/constants/app_areas.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final history = reportById('requisition-history')!;

  test('requisition history is for the store manager and admin only', () {
    expect(history.readableBy({AppAreas.inventory}), isFalse);
    expect(history.readableBy({AppAreas.sales}), isTrue);
    expect(history.readableBy({AppAreas.admin}), isTrue);
    expect(history.readableBy({AppAreas.inventory, AppAreas.sales}), isTrue);
  });

  test('every other inventory report stays open to the stock manager', () {
    for (final report in reportCatalogue) {
      if (report.section != ReportSection.inventory || report == history) continue;
      expect(report.readableBy({AppAreas.inventory}), isTrue, reason: report.id);
    }
  });
}
