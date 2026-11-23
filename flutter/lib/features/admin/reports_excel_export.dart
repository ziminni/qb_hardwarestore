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

/// The Summary sheet every workbook opens with: the same identity the viewer
/// and the letterhead PDF carry (title, period, filters, units) and then the
/// report's own totals, so a workbook opened alone still says what it is.
void _writeSummary(
  Excel excel, {
  required String title,
  required String from,
  required String to,
  required String units,
  required List<(String, CellValue)> totals,
  String? period,
}) {
  excel.rename('Sheet1', 'Summary');
  final sheet = excel['Summary'];
  // An as-of report has no range to print, so it names its own window instead.
  final window = period ?? '$from to $to';
  sheet.appendRow([_text('Field'), _text('Value')]);
  sheet.appendRow([_text('Report'), _text(title)]);
  sheet.appendRow([_text('Period'), _text(window)]);
  // These reports filter on the date range alone; naming it keeps the workbook
  // honest about the cut it was taken at.
  sheet.appendRow([_text('Filters'), _text(period ?? 'Date range $window')]);
  sheet.appendRow([_text('Units'), _text(units)]);
  for (final (label, value) in totals) {
    sheet.appendRow([_text(label), value]);
  }
}

/// A last sheet saying the workbook holds only the page in hand.
///
/// The viewer loads one 50-row page per report (`ReportPage.count` is the whole
/// range), so a truncated export that said nothing would read as the full range.
void _writeNoticeIfTruncated(Excel excel, ReportPage<Object?> page) {
  if (page.rows.length >= page.count) return;
  final notice = excel['Notice'];
  notice.appendRow([_text('Notice')]);
  notice.appendRow([
    _text(
      'This workbook holds ${page.rows.length} of ${page.count} rows the '
      'server holds. Narrow the date range to export the rest.',
    ),
  ]);
}

/// Sales & Operational Profit Breakdown workbook (3 sheets when categories exist).
Uint8List buildSalesReportXlsx(SalesSummary sales) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Profit Breakdown');

  final summary = excel['Profit Breakdown'];
  summary.appendRow([_text('Metric'), _text('Amount / Value')]);
  summary.appendRow([_text('Period'), _text('${sales.from} to ${sales.to}')]);
  summary.appendRow([
    _text('Completed transactions'),
    _int(sales.totalTransactions),
  ]);
  summary.appendRow([
    _text('Invoice total (incl. VAT & fees)'),
    _num(sales.totalGross),
  ]);
  summary.appendRow([
    _text('Goods at shelf / utang price (before discounts)'),
    _num(sales.merchandiseGross ?? 0),
  ]);
  summary.appendRow([
    _text('Discounts given (line + sale)'),
    _num(sales.totalDiscounts),
  ]);
  summary.appendRow([
    _text('VAT collected (remitted to BIR)'),
    _num(sales.totalVat),
  ]);
  summary.appendRow([
    _text('Net merchandise sales (ex-VAT)'),
    _num(sales.merchandiseNetExVat ?? sales.totalVatableSales),
  ]);
  summary.appendRow([
    _text('Landed cost of goods sold (FIFO COGS)'),
    sales.totalCogs != null
        ? _num(sales.totalCogs!)
        : _text('Missing cost history'),
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
  summary.appendRow([
    _text('Delivery fees (outside profit)'),
    _num(sales.totalDeliveryFees),
  ]);
  summary.appendRow([
    _text('Payment fees (outside profit)'),
    _num(sales.totalPaymentFees),
  ]);
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
  adj.appendRow([
    _text('Type'),
    _text('Movements'),
    _text('Quantity adjusted'),
  ]);
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
    _text('OR-Tagged Only (Official Receipt)'),
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

/// Item-wise sales workbook (Summary + Items).
Uint8List buildSalesByItemReportXlsx(SalesByItemReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Item-wise sales',
    from: report.from,
    to: report.to,
    units: 'PHP; quantity in base units',
    totals: [
      ('Selling units', _int(report.variantCount)),
      ('Units sold (base units)', _num(report.totalQtyBase)),
      ('Net merchandise', _num(report.totalNet)),
      (
        'COGS',
        report.totalCogs == null
            ? _text('No cost on file')
            : _num(report.totalCogs!),
      ),
      (
        'Gross profit',
        report.totalGrossProfit == null
            ? _text('No cost on file')
            : _num(report.totalGrossProfit!),
      ),
      ('Rows without a cost snapshot', _int(report.missingCostDeductions)),
    ],
  );

  final items = excel['Items'];
  items.appendRow([
    _text('SKU'),
    _text('Item'),
    _text('Variant'),
    _text('UOM'),
    _text('Units sold (base)'),
    _text('Gross'),
    _text('Discounts'),
    _text('Net merchandise'),
    _text('COGS'),
    _text('Gross profit'),
  ]);
  for (final row in report.page.rows) {
    items.appendRow([
      _text(row.sku),
      _text(row.product),
      _text(row.variant),
      _text(row.uom),
      _num(row.qtyBase),
      _num(row.gross),
      _num(row.discounts),
      _num(row.net),
      // An uncosted row's cost is unknown, so it is never written as 0.
      row.cogs == null ? _text('No cost on file') : _num(row.cogs!),
      row.grossProfit == null
          ? _text('No cost on file')
          : _num(row.grossProfit!),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Hourly sales workbook (Summary + Hours).
Uint8List buildSalesByHourReportXlsx(SalesByHour report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Hourly sales',
    from: report.from,
    to: report.to,
    units: 'PHP',
    totals: [
      ('Transactions', _int(report.totalTransactions)),
      ('Invoice total', _num(report.totalInvoice)),
    ],
  );

  final hours = excel['Hours'];
  hours.appendRow([
    _text('Hour (0-23)'),
    _text('Transactions'),
    _text('Invoice total'),
  ]);
  for (final row in report.page.rows) {
    hours.appendRow([
      _int(row.hour),
      _int(row.transactions),
      _num(row.invoiceTotal),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Cashier performance workbook (Summary + Cashiers).
Uint8List buildSalesByCashierReportXlsx(SalesByCashier report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Cashier performance',
    from: report.from,
    to: report.to,
    units: 'PHP',
    totals: [
      ('Transactions', _int(report.totalTransactions)),
      ('Invoice total', _num(report.totalInvoice)),
      ('Discounts', _num(report.totalDiscounts)),
    ],
  );

  final cashiers = excel['Cashiers'];
  cashiers.appendRow([
    _text('Cashier'),
    _text('Username'),
    _text('Transactions'),
    _text('Invoice total'),
    _text('Discounts'),
  ]);
  for (final row in report.page.rows) {
    cashiers.appendRow([
      _text(row.cashierName),
      _text(row.username),
      _int(row.transactions),
      _num(row.invoiceTotal),
      _num(row.discounts),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Bill-wise sales workbook (Summary + Bills, one column per tender method).
Uint8List buildBillWiseReportXlsx(BillWiseReport report) {
  final excel = Excel.createExcel();
  // Every method seen in the range gets its own numeric column, so a reader can
  // sum tenders instead of reading them out of one joined line.
  final methods = <String>{
    ...report.totalMethods.keys,
    for (final row in report.page.rows) ...row.methods.keys,
  }.toList()..sort();

  _writeSummary(
    excel,
    title: 'Bill-wise sales',
    from: report.from,
    to: report.to,
    units: 'PHP',
    totals: [
      ('Bills', _int(report.totalTransactions)),
      ('Invoice total (signed)', _num(report.totalGrand)),
      ('Discounts', _num(report.totalDiscount)),
      for (final method in methods)
        ('Tendered $method', _num(report.totalMethods[method] ?? 0)),
    ],
  );

  final bills = excel['Bills'];
  bills.appendRow([
    _text('Bill'),
    _text('OR number'),
    _text('Invoice no'),
    _text('Date'),
    _text('Cashier'),
    _text('Discount'),
    _text('Total'),
    for (final method in methods) _text('Tendered $method'),
  ]);
  for (final row in report.page.rows) {
    bills.appendRow([
      // Numbers and OR numbers carry leading zeros: text, or Excel eats them.
      _text(row.transactionNo),
      _text(row.orNumber),
      _text(row.invoiceNo),
      _text(row.date),
      _text(row.cashierName),
      _num(row.discount),
      _num(row.grandTotal),
      for (final method in methods) _num(row.methods[method] ?? 0),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Returns & exchanges workbook (Summary + Reversals).
Uint8List buildReturnsExchangesReportXlsx(ReturnsExchangesReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Returns & exchanges',
    from: report.from,
    to: report.to,
    units: 'PHP',
    totals: [
      ('Reversals', _int(report.totalTransactions)),
      ('Returns', _int(report.totalReturns)),
      ('Exchanges', _int(report.totalExchanges)),
      ('Refunded', _num(report.totalRefunded)),
    ],
  );

  final reversals = excel['Reversals'];
  reversals.appendRow([
    _text('Reversal'),
    _text('Date'),
    _text('Type'),
    _text('Original bill'),
    _text('Cashier'),
    _text('Refunded'),
    _text('Total'),
  ]);
  for (final row in report.page.rows) {
    reversals.appendRow([
      _text(row.transactionNo),
      _text(row.date),
      _text(row.source),
      _text(row.originalTransactionNo),
      _text(row.cashierName),
      _num(row.refunded),
      _num(row.grandTotal),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Discounts workbook (Summary + Discount types).
Uint8List buildDiscountsReportXlsx(DiscountsReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Discounts',
    from: report.from,
    to: report.to,
    units: 'PHP',
    totals: [
      ('Line discounts', _num(report.totalLineDiscount)),
      ('Cart discounts', _num(report.totalCartDiscount)),
      ('Total discounts (line + cart)', _num(report.totalDiscount)),
      // The cart discount on the sales a manager signed off: not extra money.
      ('Cart discount on approved sales', _num(report.totalApprovalDiscount)),
      ('Approvals', _int(report.approvals)),
    ],
  );

  final types = excel['Discount types'];
  types.appendRow([
    _text('Type'),
    _text('Transactions'),
    _text('Discount'),
    _text('Approvals'),
  ]);
  for (final row in report.page.rows) {
    types.appendRow([
      _text(row.type),
      _int(row.transactions),
      _num(row.totalDiscount),
      row.approvals == null ? _text('Not an approval') : _int(row.approvals!),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Voids workbook (Summary + Voids).
Uint8List buildVoidsReportXlsx(VoidsReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Voids',
    from: report.from,
    to: report.to,
    units: 'PHP',
    totals: [
      ('Voided bills', _int(report.totalTransactions)),
      ('Voided total', _num(report.totalVoided)),
    ],
  );

  final voids = excel['Voids'];
  voids.appendRow([
    _text('Bill'),
    _text('Date'),
    _text('Cashier'),
    _text('Amount'),
    _text('Reason'),
  ]);
  for (final row in report.page.rows) {
    final reason = row.reason?.trim() ?? '';
    voids.appendRow([
      _text(row.transactionNo),
      _text(row.date),
      _text(row.cashierName),
      _num(row.voidedTotal),
      _text(reason.isEmpty ? 'No reason recorded' : reason),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

// ---------------------------------------------------------------------------
// P2 inventory workbooks. Same shape as the P1 sales ones: a Summary sheet with
// the report's totals, the detail sheet, and a Notice sheet when the page is
// shorter than the range. Every text cell goes through `spreadsheetSafeText`, so
// a supplier or product name starting with `=`, `+`, `-` or `@` stays a name.
// A peso value the server could not cost is written as the words 'No cost on
// file' - never as 0, which would read as a claim about money.
// ---------------------------------------------------------------------------

/// Goods received workbook (Summary + Receipts).
Uint8List buildGrnReportXlsx(GrnReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Goods received',
    from: report.from,
    to: report.to,
    units: 'PHP; quantity in base units',
    totals: [
      ('Receipts', _int(report.receipts)),
      ('Line items', _int(report.items)),
      ('Quantity received', _num(report.qty)),
      ('Billed receipts', _int(report.billed)),
      ('Unbilled receipts', _int(report.unbilled)),
      ('Bill total', _num(report.billTotal)),
    ],
  );

  final receipts = excel['Receipts'];
  receipts.appendRow([
    _text('Receipt'),
    _text('Date'),
    _text('Supplier'),
    _text('Items'),
    _text('Quantity'),
    _text('Bill'),
    _text('Bill total'),
    _text('Bill status'),
  ]);
  for (final row in report.page.rows) {
    receipts.appendRow([
      _text(row.deliveryReceiptNo),
      _text(row.date),
      _text(row.supplier),
      _int(row.items),
      _num(row.qty),
      _text(row.billTotal == null ? 'Not billed' : 'Billed'),
      row.billTotal == null ? _text('Not billed') : _num(row.billTotal!),
      _text(row.billStatus ?? 'Not billed'),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Stock transfers workbook (Summary + Transfers).
Uint8List buildStnReportXlsx(StnReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Stock transfers',
    from: report.from,
    to: report.to,
    units: 'Quantity in base units',
    totals: [
      ('Transfer slips', _int(report.transfers)),
      ('Line items', _int(report.lines)),
      ('Quantity moved', _num(report.qty)),
    ],
  );

  final transfers = excel['Transfers'];
  transfers.appendRow([
    _text('Transfer'),
    _text('Date'),
    _text('From'),
    _text('To'),
    _text('Lines'),
    _text('Quantity'),
    _text('Status'),
  ]);
  for (final row in report.page.rows) {
    transfers.appendRow([
      _text(row.number),
      _text(row.date),
      _text(row.fromLocationName),
      _text(row.toLocationName),
      _int(row.lines),
      _num(row.qty),
      _text(row.status),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Batch age workbook (Summary + Batch age): on-hand quantity per age band.
Uint8List buildBatchAgeReportXlsx(BatchAgeReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Batch age',
    from: report.asOf,
    to: report.asOf,
    period: 'As of ${report.asOf}',
    units: 'Quantity in base units',
    totals: [
      ('Variants on hand', _int(report.variants)),
      ('0-30 days', _num(report.qty0to30)),
      ('31-90 days', _num(report.qty30to90)),
      ('90+ days', _num(report.qty90plus)),
      ('On hand', _num(report.totalQty)),
    ],
  );

  final age = excel['Batch age'];
  age.appendRow([
    _text('SKU'),
    _text('Item'),
    _text('Variant'),
    _text('UOM'),
    _text('Oldest batch (days)'),
    _text('0-30 days'),
    _text('31-90 days'),
    _text('90+ days'),
    _text('On hand'),
  ]);
  for (final row in report.page.rows) {
    age.appendRow([
      _text(row.sku),
      _text(row.product),
      _text(row.variant),
      _text(row.uom),
      _int(row.oldestAgeDays),
      _num(row.qty0to30),
      _num(row.qty30to90),
      _num(row.qty90plus),
      _num(row.totalQty),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Shrinkage & damage workbook (Summary + Shrinkage).
Uint8List buildShrinkageReportXlsx(ShrinkageReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Shrinkage & damage',
    from: report.from,
    to: report.to,
    units: 'PHP; quantity in base units',
    totals: [
      ('Quantity lost', _num(report.qty)),
      (
        'Value lost',
        report.totalValue == null
            ? _text('No cost on file')
            : _num(report.totalValue!),
      ),
      ('Loss rows without a cost', _int(report.missingCostLines)),
      ('Adjustments', _int(report.adjustments)),
      ('Stock available', _num(report.openingQty + report.receivedQty)),
      (
        'Shrinkage (%)',
        report.shrinkagePercent == null
            ? _text('No stock to measure')
            : _num(report.shrinkagePercent!),
      ),
    ],
  );

  final shrinkage = excel['Shrinkage'];
  shrinkage.appendRow([
    _text('Date'),
    _text('Quantity lost'),
    _text('Value lost'),
    _text('Adjustments'),
  ]);
  for (final row in report.page.rows) {
    shrinkage.appendRow([
      _text(row.date),
      _num(row.qty),
      // A day made only of uncosted losses has no peso value: say so.
      row.value == null ? _text('No cost on file') : _num(row.value!),
      _int(row.adjustments),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Stock adjustments workbook (Summary + Adjustments).
Uint8List buildAdjustmentsReportXlsx(AdjustmentsReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Stock adjustments',
    from: report.from,
    to: report.to,
    units: 'PHP; signed quantities in base units',
    totals: [
      ('Adjustments', _int(report.adjustments)),
      ('Quantity (signed)', _num(report.qty)),
      (
        'Value (signed)',
        report.totalValue == null
            ? _text('No cost on file')
            : _num(report.totalValue!),
      ),
      ('Rows without a cost', _int(report.missingCostLines)),
    ],
  );

  final adjustments = excel['Adjustments'];
  adjustments.appendRow([
    _text('Date'),
    _text('Type'),
    _text('Item'),
    _text('Variant'),
    _text('Shelf'),
    _text('Recorded by'),
    _text('Quantity (signed)'),
    _text('Value'),
  ]);
  for (final row in report.page.rows) {
    adjustments.appendRow([
      _text(row.date),
      _text(row.type),
      _text(row.product),
      _text(row.variant),
      _text(row.locationName),
      _text(row.userName),
      _num(row.qty),
      row.value == null ? _text('No cost on file') : _num(row.value!),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Reorder list workbook (Summary + Reorder), one row per variant with its shelves.
Uint8List buildReorderReportXlsx(ReorderReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Reorder list',
    from: '',
    to: '',
    period: 'As of today',
    units: 'Quantity in base units',
    totals: [
      ('Variants to reorder', _int(report.variants)),
      ('On hand', _num(report.onHand)),
      ('Minimum stock', _num(report.threshold)),
      ('Shortfall to buy', _num(report.gap)),
    ],
  );

  final reorder = excel['Reorder'];
  reorder.appendRow([
    _text('SKU'),
    _text('Item'),
    _text('Variant'),
    _text('UOM'),
    _text('On hand'),
    _text('Minimum'),
    _text('Shortfall'),
    _text('Shelves'),
  ]);
  for (final row in report.page.rows) {
    reorder.appendRow([
      _text(row.sku),
      _text(row.product),
      _text(row.variant),
      _text(row.uom),
      _num(row.onHand),
      _num(row.threshold),
      _num(row.gap),
      _text(
        [
          for (final shelf in row.locations)
            '${shelf.locationName} ${shelf.qty}',
        ].join(' · '),
      ),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Dead stock workbook (Summary + Dead stock).
Uint8List buildDeadStockReportXlsx(DeadStockReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Dead stock',
    from: report.from,
    to: report.to,
    units: 'PHP; quantity in base units',
    totals: [
      ('Trailing window (days)', _int(report.days)),
      ('Variants with no sales', _int(report.variants)),
      ('On hand', _num(report.onHand)),
      ('Money tied up', _num(report.landedValue)),
    ],
  );

  final dead = excel['Dead stock'];
  dead.appendRow([
    _text('SKU'),
    _text('Item'),
    _text('Variant'),
    _text('UOM'),
    _text('On hand'),
    _text('Days since last sale'),
    _text('Money tied up'),
  ]);
  for (final row in report.page.rows) {
    dead.appendRow([
      _text(row.sku),
      _text(row.product),
      _text(row.variant),
      _text(row.uom),
      _num(row.onHand),
      row.daysSinceLastSale == null
          ? _text('Never sold')
          : _int(row.daysSinceLastSale!),
      _num(row.landedValue),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Fast & slow movers workbook (Summary + Movers).
Uint8List buildFastSlowReportXlsx(FastSlowReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Fast & slow movers',
    from: report.from,
    to: report.to,
    units: 'PHP; quantity in base units',
    totals: [
      ('SKUs sold', _int(report.skusSold)),
      ('Fast movers', _int(report.fast)),
      ('Slow movers', _int(report.slow)),
      ('Units sold', _num(report.qtyBase)),
      ('Net merchandise', _num(report.netMerchandise)),
    ],
  );

  final movers = excel['Movers'];
  movers.appendRow([
    _text('Band'),
    _text('SKU'),
    _text('Item'),
    _text('Variant'),
    _text('UOM'),
    _text('Units sold'),
    _text('Net merchandise'),
  ]);
  for (final row in report.page.rows) {
    movers.appendRow([
      _text(row.band),
      _text(row.sku),
      _text(row.product),
      _text(row.variant),
      _text(row.uom),
      _num(row.qtyBase),
      _num(row.netMerchandise),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Cycle count workbook (Summary + Cycle count).
Uint8List buildCycleCountReportXlsx(CycleCountReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Cycle count',
    from: report.from,
    to: report.to,
    units: 'PHP; signed quantities in base units',
    totals: [
      ('Count corrections', _int(report.adjustments)),
      ('Net variance (signed)', _num(report.qty)),
      (
        'Value of variance',
        report.totalValue == null
            ? _text('No cost on file')
            : _num(report.totalValue!),
      ),
      ('Rows without a cost', _int(report.missingCostLines)),
      ('On hand now', _num(report.onHandQty)),
      (
        'Shrinkage (%)',
        report.shrinkagePercent == null
            ? _text('No stock to measure')
            : _num(report.shrinkagePercent!),
      ),
    ],
  );

  final count = excel['Cycle count'];
  count.appendRow([
    _text('Date'),
    _text('Item'),
    _text('Variant'),
    _text('Shelf'),
    _text('Counted by'),
    _text('Variance'),
    _text('Value'),
  ]);
  for (final row in report.page.rows) {
    count.appendRow([
      _text(row.date),
      _text(row.product),
      _text(row.variant),
      _text(row.locationName),
      _text(row.userName),
      _num(row.qty),
      row.value == null ? _text('No cost on file') : _num(row.value!),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}

/// Expiry workbook (Summary + Expiry), one row per stocked batch.
Uint8List buildExpiryReportXlsx(ExpiryReport report) {
  final excel = Excel.createExcel();
  _writeSummary(
    excel,
    title: 'Expiry',
    from: report.asOf,
    to: report.asOf,
    period: 'As of ${report.asOf}',
    units: 'PHP; quantity in base units',
    totals: [
      ('Window (days)', _int(report.days)),
      ('Batches expiring', _int(report.rowCount)),
      ('Quantity at risk', _num(report.qty)),
      ('Value at risk', _num(report.value)),
      ('Already expired', _num(report.valueExpired)),
      ('Expiring 0-30 days', _num(report.value0to30)),
      ('Expiring 31-60 days', _num(report.value31to60)),
      ('Expiring 61-90 days', _num(report.value61to90)),
      (
        'Near-expiry (%)',
        report.nearExpiryPct == null
            ? _text('No stock on hand')
            : _num(report.nearExpiryPct!),
      ),
    ],
  );

  final expiry = excel['Expiry'];
  expiry.appendRow([
    _text('SKU'),
    _text('Item'),
    _text('Variant'),
    _text('UOM'),
    _text('Shelf'),
    _text('Expires on'),
    _text('Days left'),
    _text('Bucket'),
    _text('Quantity'),
    _text('Value'),
  ]);
  for (final row in report.page.rows) {
    expiry.appendRow([
      _text(row.sku),
      _text(row.product),
      _text(row.variant),
      _text(row.uom),
      _text(row.location),
      _text(row.expiresOn),
      _int(row.daysLeft),
      _text(row.bucket),
      _num(row.qty),
      _num(row.value),
    ]);
  }
  _writeNoticeIfTruncated(excel, report.page);

  return _encode(excel);
}
