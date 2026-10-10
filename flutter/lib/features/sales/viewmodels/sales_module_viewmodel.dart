import 'package:client/data/models/sales_module.dart';
import 'package:flutter/foundation.dart';

class SalesModuleViewmodel extends ChangeNotifier {
  final quotations = <SalesQuotation>[
    SalesQuotation(
      'QT-2026-0041',
      'JDL Construction',
      DateTime(2026, 9, 24),
      DateTime(2026, 10, 8),
      48250,
      SalesQuoteStatus.sent,
    ),
    SalesQuotation(
      'QT-2026-0040',
      'Ramos Builders',
      DateTime(2026, 9, 23),
      DateTime(2026, 10, 7),
      18740,
      SalesQuoteStatus.accepted,
    ),
    SalesQuotation(
      'QT-2026-0039',
      'M. Santos',
      DateTime(2026, 9, 21),
      DateTime(2026, 10, 5),
      9360,
      SalesQuoteStatus.draft,
    ),
    SalesQuotation(
      'QT-2026-0038',
      'Northline Works',
      DateTime(2026, 9, 10),
      DateTime(2026, 9, 20),
      72900,
      SalesQuoteStatus.expired,
    ),
  ];
  final orders = <SalesOrderRecord>[
    SalesOrderRecord(
      'SO-2026-0027',
      'Ramos Builders',
      DateTime(2026, 9, 25),
      18740,
      SalesOrderStatus.processing,
    ),
    SalesOrderRecord(
      'SO-2026-0026',
      'JDL Construction',
      DateTime(2026, 9, 24),
      52600,
      SalesOrderStatus.ready,
    ),
    SalesOrderRecord(
      'SO-2026-0025',
      'M. Santos',
      DateTime(2026, 9, 22),
      12150,
      SalesOrderStatus.confirmed,
    ),
    SalesOrderRecord(
      'SO-2026-0024',
      'Northline Works',
      DateTime(2026, 9, 20),
      63800,
      SalesOrderStatus.completed,
    ),
  ];
  final customers = const <SalesCustomerRecord>[
    SalesCustomerRecord(
      'CUS-0012',
      'JDL Construction',
      '0917 555 0182',
      'Contractor',
      18,
      286400,
    ),
    SalesCustomerRecord(
      'CUS-0011',
      'Ramos Builders',
      '0918 440 3271',
      'Contractor',
      12,
      174250,
    ),
    SalesCustomerRecord(
      'CUS-0010',
      'Northline Works',
      'northline@example.com',
      'Business',
      9,
      131800,
    ),
    SalesCustomerRecord(
      'CUS-0009',
      'M. Santos',
      '0920 116 8042',
      'Individual',
      5,
      28750,
    ),
  ];
  final receivables = <SalesReceivableRecord>[
    SalesReceivableRecord(
      'INV-2026-0098',
      'JDL Construction',
      DateTime(2026, 10, 10),
      52600,
      20000,
      SalesReceivableStatus.current,
    ),
    SalesReceivableRecord(
      'INV-2026-0095',
      'Ramos Builders',
      DateTime(2026, 9, 30),
      18740,
      10000,
      SalesReceivableStatus.dueSoon,
    ),
    SalesReceivableRecord(
      'INV-2026-0087',
      'Northline Works',
      DateTime(2026, 9, 18),
      63800,
      30000,
      SalesReceivableStatus.overdue,
    ),
  ];
}
