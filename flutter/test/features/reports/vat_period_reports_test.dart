import 'package:client/data/models/reports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VatReportSummary parses OR-backed vs untagged OS VAT breakdown and periods', () {
    final report = VatReportSummary.fromJson({
      'from': '2026-11-01',
      'to': '2026-11-22',
      'granularity': 'month',
      'totals': {
        'or_backed': {
          'transactions': 2,
          'gross_sales': '224.00',
          'vatable_sales': '200.00',
          'vat': '24.00',
        },
        'untagged_os': {
          'transactions': 5,
          'gross_sales': '560.00',
          'vatable_sales': '500.00',
          'vat': '60.00',
        },
        'combined': {
          'transactions': 7,
          'gross_sales': '784.00',
          'vatable_sales': '700.00',
          'vat': '84.00',
        },
      },
      'by_period': [
        {
          'period': '2026-11',
          'transactions': 7,
          'gross_sales': '784.00',
          'vat': '84.00',
          'or_backed_transactions': 2,
          'or_backed_sales': '224.00',
          'or_backed_vatable': '200.00',
          'or_backed_vat': '24.00',
          'untagged_transactions': 5,
          'untagged_sales': '560.00',
          'untagged_vatable': '500.00',
          'untagged_vat': '60.00',
        },
      ],
    });

    expect(report.granularity, 'month');
    expect(report.totals.orBacked.vat, 24.0);
    expect(report.totals.untaggedOs.vat, 60.0);
    expect(report.totals.combined.vat, 84.0);
    expect(report.periods.single.period, '2026-11');
    expect(report.periods.single.orBackedVat, 24.0);
  });
}
