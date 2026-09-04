class DashboardMetricData {
  const DashboardMetricData(this.label, this.value);

  final String label;
  final String value;
}

class DashboardListItemData {
  const DashboardListItemData(this.title, this.subtitle, [this.trailing]);

  final String title;
  final String subtitle;
  final String? trailing;
}

class DashboardTableData {
  const DashboardTableData({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;
}

class DashboardMockData {
  const DashboardMockData._();

  static const adminMetrics = [
    DashboardMetricData('Today sales', '₱84,250'),
    DashboardMetricData('Products', '1,248'),
    DashboardMetricData('Low stock', '23'),
    DashboardMetricData('Active users', '18'),
  ];

  static const adminQuickActions = [
    'Create user',
    'Add product',
    'View reports',
    'Settings',
  ];

  static const adminRecentActivity = [
    DashboardListItemData(
      'Cashier Maria signed in',
      'POS Terminal 02 · 8 minutes ago',
    ),
    DashboardListItemData(
      'Stock receipt SR-1042 completed',
      '124 items added · 24 minutes ago',
    ),
    DashboardListItemData(
      'Portland Cement price updated',
      'Inventory Staff · 1 hour ago',
    ),
  ];

  static const adminAlerts = [
    DashboardListItemData('PVC Pipe 1/2"', '4 units remaining', 'Critical'),
    DashboardListItemData('Marine Plywood', '8 units remaining', 'Low stock'),
  ];

  static const inventoryMetrics = [
    DashboardMetricData('Total products', '1,248'),
    DashboardMetricData('Inventory value', '₱3.84M'),
    DashboardMetricData('Low stock', '23'),
    DashboardMetricData('Out of stock', '7'),
  ];

  static const inventoryTable = DashboardTableData(
    columns: ['Product', 'Category', 'On hand', 'Reorder level', 'Status'],
    rows: [
      ['Portland Cement 40kg', 'Cement', '128', '50', 'Healthy'],
      ['PVC Pipe 1/2"', 'Plumbing', '4', '20', 'Critical'],
      ['Marine Plywood 1/4', 'Lumber', '8', '15', 'Low stock'],
    ],
  );

  static const stockMovements = [
    DashboardListItemData('Portland Cement 40kg', 'SR-1042 · 10:42 AM', '+80'),
    DashboardListItemData('PVC Pipe 1/2"', 'POS-8921 · 10:18 AM', '-12'),
  ];

  static const restockQueue = [
    DashboardListItemData('PVC Pipe 1/2"', 'Suggested order: 50', 'Critical'),
    DashboardListItemData('Marine Plywood', 'Suggested order: 30', 'Low'),
  ];

  static const salesMetrics = [
    DashboardMetricData('Gross sales', '₱84,250'),
    DashboardMetricData('Transactions', '126'),
    DashboardMetricData('Average sale', '₱668.65'),
    DashboardMetricData('Items sold', '384'),
  ];

  static const recentTransactions = DashboardTableData(
    columns: ['Receipt', 'Date / Time', 'Cashier', 'Items', 'Payment', 'Total'],
    rows: [
      ['#8921', 'Today, 10:18 AM', 'Maria Santos', '12', 'Cash', '₱2,840'],
      ['#8920', 'Today, 10:05 AM', 'Maria Santos', '4', 'Card', '₱1,275'],
      ['#8919', 'Today, 9:47 AM', 'John Cruz', '8', 'Cash', '₱3,120'],
    ],
  );

  static const posSubtotal = '₱2,840.00';
  static const posDiscount = '₱0.00';
  static const posTax = '₱0.00';
  static const posTotal = '₱2,840.00';
  static const posCartSummary = '12 items in the current transaction';
}
