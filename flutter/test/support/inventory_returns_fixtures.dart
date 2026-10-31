// Card K9: the stock manager's Returns list reads the RETURN rows the shared
// viewmodel splits out of the transactions payload, so the fixtures here are
// wire-shaped `TransactionRecord`s (negative quantities and a negative grand
// total are what the server sends for a return).
//
// The service stub and the provider wrapper are reused from the S1 fixture file
// instead of copied: both cards read the same viewmodel, so a change there must
// break one file, not two.

import 'package:client/data/models/sale_transaction.dart';

/// Four posted returns covering what the list and its sheet must survive: a
/// plain two-unit return, a LONG product code with a SEVEN DIGIT refund, a
/// return with no original sale on the wire, and a voided one.
///
/// Quantities are distinct on purpose, so a test can name one row's units
/// without matching another's.
List<TransactionRecord> inventoryReturnsFixture() => [
  _return(
    id: 120,
    no: 'TRX-20261030-0002',
    at: DateTime(2026, 10, 30, 14, 14),
    originalId: 91,
    status: 'COMPLETED',
    lines: [_line('BAG', 2, 250)],
  ),
  _return(
    id: 121,
    no: 'TRX-20261030-0001',
    at: DateTime(2026, 10, 30, 9, 5),
    originalId: 90,
    status: 'COMPLETED',
    lines: [_line('CEM-40KG', 1200, 950)],
  ),
  _return(
    id: 122,
    no: 'TRX-20261029-0004',
    at: DateTime(2026, 10, 29, 16, 40),
    // No original sale on the wire: the viewmodel writes a dash, the page a
    // word (D18).
    originalId: null,
    status: 'VOID',
    lines: [_line('PIPE-2IN', 1, 240)],
  ),
  _return(
    id: 123,
    no: 'TRX-20261029-0003',
    at: DateTime(2026, 10, 29, 11, 20),
    originalId: 88,
    status: 'COMPLETED',
    lines: [_line('MARINE-PLYWOOD-3QTR-4X8-SHEET', 6, 1480.50)],
  ),
];

/// A `source='RETURN'` transaction: what `InventorySalesViewmodel.load` splits
/// into its `returns` list.
TransactionRecord _return({
  required int id,
  required String no,
  required DateTime at,
  required int? originalId,
  required String status,
  required List<TransactionLineItem> lines,
}) => TransactionRecord(
  id: id,
  transactionNo: no,
  transDate: at,
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  cashierName: 'Ana Reyes',
  source: 'RETURN',
  originalTransactionId: originalId,
  status: status,
  grandTotal: lines.fold<double>(0, (sum, line) => sum + line.subtotal),
  items: lines,
  payments: const [],
);

/// One returned line. The server sends returned quantities negative; the page
/// shows the magnitude, because "units back" is stock coming in.
TransactionLineItem _line(String code, double qty, double unitPrice) =>
    TransactionLineItem(
      variantUomId: 42,
      variantUomCode: code,
      qty: -qty,
      unitPrice: unitPrice,
      subtotal: -qty * unitPrice,
    );
