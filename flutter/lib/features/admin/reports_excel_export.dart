import 'dart:typed_data';

import 'package:client/core/format/spreadsheet_text.dart';
import 'package:client/data/models/reports.dart';
import 'package:excel_community/excel_community.dart';

/// Builds Excel (.xlsx) workbooks for all four admin/sales report tabs.
///
/// Uses `spreadsheetSafeText` on every text cell so user-entered names starting
/// with `=`, `+`, `-`, or `@` never execute as spreadsheet formulas.

CellValue _text(String value) => TextCellValue(spreadsheetSafeText(value));
CellValue _num(double value) => DoubleCellValue(value);
CellValue _int(int value) => IntCellValue(value);

Uint8List _encode(Excel excel) =>
    Uint8List.fromList(excel.encode() ?? const <int>[]);

/// Sales & Operational Profit Breakdown workbook (3 sheets when categories exist).
Uint8List buildSalesReportXlsx(SalesSummary sales) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Profit Breakdown');

  final summary = excel['Profit Breakdown'];
  summary.appendRow([_text('Metric'), _text('Amount / Value')]);
  summary.appendRow([_text('Period'), _text('${sales.from} to ${sales.to}')]);
  summary.appendRow([_text('Completed transactions'), _int(sales.totalTransactions)]);
  summary.appendRow([_text('Invoice total (incl. VAT & fees)'), _num(sales.totalGross)]);
  summary.appendRow([
    _text('Goods at shelf / utang price (before discounts)'),
    _num(sales.merchandiseGross ?? 0),
  ]);
  summary.appendRow([_text('Discounts given (line + sale)'), _num(sales.totalDiscounts)]);
  summary.appendRow([_text('VAT collected (remitted to BIR)'), _num(sales.totalVat)]);
  summary.appendRow([
    _text('Net merchandise sales (ex-VAT)'),
    _num(sales.merchandiseNetExVat ?? sales.totalVatableSales),
  ]);
  summary.appendRow([
    _text('Landed cost of goods sold (FIFO COGS)'),
    sales.totalCogs != null ? _num(sales.totalCogs!) : _text('Missing cost history'),
  ]);
  summary.appendRow([
    _text('Operational gross profit'),
    sales.grossProfit != null ? _num(sales.grossProfit!) : _text('Unavailable'),
  ]);
  if (sales.grossMarginPercent != null) {
    summary.appendRow([
      _text('Gross margin (%)'),
      _num(sales.grossMarginPercent!),
    ]);
  }
  if (sales.effectiveMarkupPercent != null) {
    summary.appendRow([
      _text('Effective markup on cost (%)'),
      _num(sales.effectiveMarkupPercent!),
    ]);
  }
  summary.appendRow([_text('Delivery fees (outside profit)'), _num(sales.totalDeliveryFees)]);
  summary.appendRow([_text('Payment fees (outside profit)'), _num(sales.totalPaymentFees)]);
  summary.appendRow([
    _text('Cost coverage'),
    _text(
      sales.costCoverage.complete
          ? 'Complete (${sales.costCoverage.costedDeductions} costed rows)'
          : 'Partial (${sales.costCoverage.missingCostDeductions} older rows without cost snapshot)',
    ),
  ]);

  final daily = excel['Daily Sales'];
  daily.appendRow([
    _text('Day'),
    _text('Transactions'),
    _text('Invoice total'),
    _text('Discounts'),
    _text('VAT'),
    _text('Payment fees'),
    _text('Net sales (ex-VAT)'),
    _text('COGS'),
    _text('Gross profit'),
  ]);
  for (final day in sales.days) {
    daily.appendRow([
      _text(day.day),
      _int(day.transactions),
      _num(day.gross),
      _num(day.discounts),
      _num(day.vat),
      _num(day.paymentFees),
      _num(day.merchandiseNetExVat ?? 0),
      day.cogs != null ? _num(day.cogs!) : _text(''),
      day.grossProfit != null ? _num(day.grossProfit!) : _text(''),
    ]);
  }
  if (sales.days.isNotEmpty) {
    daily.appendRow([
      _text('Total'),
      _int(sales.totalTransactions),
      _num(sales.totalGross),
      _num(sales.totalDiscounts),
      _num(sales.totalVat),
      _num(sales.totalPaymentFees),
      _num(sales.merchandiseNetExVat ?? sales.totalVatableSales),
      sales.totalCogs != null ? _num(sales.totalCogs!) : _text(''),
      sales.grossProfit != null ? _num(sales.grossProfit!) : _text(''),
    ]);
  }

  if (sales.categories.isNotEmpty) {
    final cats = excel['By Category'];
    cats.appendRow([
      _text('Category'),
      _text('Gross merchandise'),
      _text('Discounts'),
      _text('Net merchandise'),
      _text('COGS'),
    ]);
    for (final cat in sales.categories) {
      cats.appendRow([
        _text(cat.categoryName),
        _num(cat.grossMerchandise),
        _num(cat.discounts),
        _num(cat.netMerchandise),
        cat.cogs != null ? _num(cat.cogs!) : _text(''),
      ]);
    }
  }

  return _encode(excel);
}

/// Inventory Valuation workbook (By Category + By Location).
Uint8List buildValuationReportXlsx(InventoryValuation valuation) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'By Category');

  final cats = excel['By Category'];
  cats.appendRow([
    _text('Category'),
    _text('Batches'),
    _text('Units on hand'),
    _text('Value at cost'),
    _text('Value at retail'),
    _text('Potential markup'),
  ]);
  for (final cat in valuation.categories) {
    cats.appendRow([
      _text(cat.name),
      _int(cat.batchCount),
      _num(cat.units),
      _num(cat.cost),
      _num(cat.retail),
      _num(cat.retail - cat.cost),
    ]);
  }
  cats.appendRow([
    _text('Total'),
    _int(valuation.batchCount),
    _num(valuation.totalUnits),
    _num(valuation.totalCost),
    _num(valuation.totalRetail),
    _num(valuation.totalRetail - valuation.totalCost),
  ]);

  if (valuation.locations.isNotEmpty) {
    final locs = excel['By Location'];
    locs.appendRow([
      _text('Location'),
      _text('Batches'),
      _text('Units on hand'),
      _text('Value at cost'),
      _text('Value at retail'),
    ]);
    for (final loc in valuation.locations) {
      locs.appendRow([
        _text(loc.locationName),
        _int(loc.batchCount),
        _num(loc.units),
        _num(loc.cost),
        _num(loc.retail),
      ]);
    }
  }

  return _encode(excel);
}

/// Stock Movements workbook (Goods Received + Adjustments).
Uint8List buildMovementsReportXlsx(StockMovements movements) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Goods Received');

  final received = excel['Goods Received'];
  received.appendRow([_text('Date'), _text('Receipts'), _text('Quantity in')]);
  for (final day in movements.receiptsByDay) {
    received.appendRow([_text(day.date), _int(day.receipts), _num(day.qtyIn)]);
  }
  received.appendRow([_text('Total'), _text(''), _num(movements.totalIn)]);

  final adj = excel['Adjustments'];
  adj.appendRow([_text('Type'), _text('Movements'), _text('Quantity adjusted')]);
  for (final type in movements.adjustmentsByType) {
    adj.appendRow([_text(type.type), _int(type.movements), _num(type.qtyOut)]);
  }
  adj.appendRow([_text('Total'), _text(''), _num(movements.totalOut)]);

  return _encode(excel);
}

/// Requisition History workbook.
Uint8List buildRequisitionsReportXlsx(RequisitionHistory history) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Requisitions');

  final sheet = excel['Requisitions'];
  sheet.appendRow([
    _text('Requisition'),
    _text('Status'),
    _text('Project'),
    _text('Requested by'),
    _text('Approved by'),
  ]);
  for (final row in history.requisitions) {
    sheet.appendRow([
      _text(row.reqNumber),
      _text(row.status),
      _text(row.project),
      _text(row.requestedBy),
      _text(row.approvedBy ?? 'Not approved'),
    ]);
  }

  return _encode(excel);
}

/// Whole VAT vs. BIR OR-Only VAT workbook (2 sheets: VAT Summary & By Period).
Uint8List buildVatReportXlsx(VatReportSummary report) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'VAT Summary');

  final summary = excel['VAT Summary'];
  summary.appendRow([
    _text('Bucket'),
    _text('Transactions'),
    _text('Gross sales'),
    _text('Vatable sales'),
    _text('VAT amount'),
  ]);
  summary.appendRow([
    _text('Whole VAT (All Sales)'),
    _int(report.totals.combined.transactions),
    _num(report.totals.combined.grossSales),
    _num(report.totals.combined.vatableSales),
    _num(report.totals.combined.vat),
  ]);
  summary.appendRow([
    _text('BIR OR Only (Official Receipt)'),
    _int(report.totals.orBacked.transactions),
    _num(report.totals.orBacked.grossSales),
    _num(report.totals.orBacked.vatableSales),
    _num(report.totals.orBacked.vat),
  ]);
  summary.appendRow([
    _text('Untagged Order Slips (OS)'),
    _int(report.totals.untaggedOs.transactions),
    _num(report.totals.untaggedOs.grossSales),
    _num(report.totals.untaggedOs.vatableSales),
    _num(report.totals.untaggedOs.vat),
  ]);

  final periods = excel['By Period'];
  periods.appendRow([
    _text('Period (${report.granularity})'),
    _text('OR Transactions'),
    _text('OR Gross Sales'),
    _text('OR Vatable Sales'),
    _text('OR VAT'),
    _text('Untagged OS Transactions'),
    _text('Untagged OS Sales'),
    _text('Untagged OS VAT'),
    _text('Whole VAT'),
  ]);
  for (final row in report.periods) {
    periods.appendRow([
      _text(row.period),
      _int(row.orBackedTransactions),
      _num(row.orBackedSales),
      _num(row.orBackedVatable),
      _num(row.orBackedVat),
      _int(row.untaggedTransactions),
      _num(row.untaggedSales),
      _num(row.untaggedVat),
      _num(row.vat),
    ]);
  }
  periods.appendRow([
    _text('Total'),
    _int(report.totals.orBacked.transactions),
    _num(report.totals.orBacked.grossSales),
    _num(report.totals.orBacked.vatableSales),
    _num(report.totals.orBacked.vat),
    _int(report.totals.untaggedOs.transactions),
    _num(report.totals.untaggedOs.grossSales),
    _num(report.totals.untaggedOs.vat),
    _num(report.totals.combined.vat),
  ]);

  return _encode(excel);
}
