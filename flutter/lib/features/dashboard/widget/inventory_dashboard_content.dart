import 'package:client/core/constants/app_colors.dart';
import 'package:client/features/dashboard/widget/dashboard_components.dart';
import 'package:flutter/material.dart';

class InventoryDashboardContent extends StatelessWidget {
  const InventoryDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Inventory overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepBlack,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.file_download_outlined, size: 17),
              label: const Text('Export'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add product'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepBlack,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 920 ? 4 : 2;
            const spacing = 16.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: width,
                  child: const MetricCard(
                    label: 'Total products',
                    value: '1,248',
                    icon: Icons.category_outlined,
                    color: AppColors.info,
                    change: '+18',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const MetricCard(
                    label: 'Inventory value',
                    value: '₱3.84M',
                    icon: Icons.account_balance_wallet_outlined,
                    color: AppColors.success,
                    change: '+4.2%',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const MetricCard(
                    label: 'Low stock',
                    value: '23',
                    icon: Icons.production_quantity_limits_outlined,
                    color: AppColors.warning,
                    change: '+5',
                    changeIsPositive: false,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const MetricCard(
                    label: 'Out of stock',
                    value: '7',
                    icon: Icons.remove_shopping_cart_outlined,
                    color: AppColors.error,
                    change: '+2',
                    changeIsPositive: false,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        DashboardPanel(
          title: 'Stock levels',
          subtitle: 'Products that need monitoring or replenishment',
          action: SizedBox(
            width: 230,
            height: 38,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search inventory',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          child: const _InventoryTable(),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final movements = DashboardPanel(
              title: 'Recent stock movements',
              subtitle: 'Latest incoming and outgoing inventory',
              child: const Column(
                children: [
                  _MovementRow(
                    reference: 'SR-1042',
                    product: 'Portland Cement 40kg',
                    quantity: '+80',
                    time: '10:42 AM',
                    incoming: true,
                  ),
                  Divider(height: 30),
                  _MovementRow(
                    reference: 'POS-8921',
                    product: 'PVC Pipe 1/2"',
                    quantity: '-12',
                    time: '10:18 AM',
                    incoming: false,
                  ),
                  Divider(height: 30),
                  _MovementRow(
                    reference: 'ADJ-0318',
                    product: 'Common Wire Nails 2"',
                    quantity: '-3',
                    time: '9:35 AM',
                    incoming: false,
                  ),
                ],
              ),
            );
            final restock = DashboardPanel(
              title: 'Restock queue',
              subtitle: 'Suggested purchase orders',
              action: TextButton(
                onPressed: () {},
                child: const Text('Review all'),
              ),
              child: const Column(
                children: [
                  _RestockRow(
                    product: 'PVC Pipe 1/2"',
                    suggested: 'Order 50',
                    urgency: 'Critical',
                    color: AppColors.error,
                  ),
                  Divider(height: 28),
                  _RestockRow(
                    product: 'Marine Plywood',
                    suggested: 'Order 30',
                    urgency: 'Low',
                    color: AppColors.warning,
                  ),
                  Divider(height: 28),
                  _RestockRow(
                    product: 'Roofing Nails',
                    suggested: 'Order 20',
                    urgency: 'Low',
                    color: AppColors.warning,
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 900) {
              return Column(
                children: [movements, const SizedBox(height: 20), restock],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: movements),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: restock),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InventoryTable extends StatelessWidget {
  const _InventoryTable();

  @override
  Widget build(BuildContext context) {
    const rows = [
      (
        'Portland Cement 40kg',
        'Cement',
        '128',
        '50',
        'Healthy',
        AppColors.success,
      ),
      ('PVC Pipe 1/2"', 'Plumbing', '4', '20', 'Critical', AppColors.error),
      (
        'Marine Plywood 1/4',
        'Lumber',
        '8',
        '15',
        'Low stock',
        AppColors.warning,
      ),
      (
        'Common Wire Nails 2"',
        'Fasteners',
        '86',
        '30',
        'Healthy',
        AppColors.success,
      ),
      (
        'Acrylic Latex Paint',
        'Paint',
        '0',
        '10',
        'Out of stock',
        AppColors.error,
      ),
    ];

    return Column(
      children: [
        const _TableRow(
          product: 'PRODUCT',
          category: 'CATEGORY',
          onHand: 'ON HAND',
          reorder: 'REORDER AT',
          status: 'STATUS',
          header: true,
        ),
        const Divider(height: 1),
        for (final row in rows) ...[
          _TableRow(
            product: row.$1,
            category: row.$2,
            onHand: row.$3,
            reorder: row.$4,
            status: row.$5,
            statusColor: row.$6,
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.product,
    required this.category,
    required this.onHand,
    required this.reorder,
    required this.status,
    this.statusColor,
    this.header = false,
  });

  final String product;
  final String category;
  final String onHand;
  final String reorder;
  final String status;
  final Color? statusColor;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: header ? 10 : 12,
      fontWeight: header ? FontWeight.w700 : FontWeight.w500,
      color: header ? AppColors.textSecondary : AppColors.deepBlack,
      letterSpacing: header ? 0.4 : 0,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: header ? 10 : 14),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(product, style: style)),
          Expanded(flex: 2, child: Text(category, style: style)),
          Expanded(child: Text(onHand, style: style)),
          Expanded(child: Text(reorder, style: style)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: header
                  ? Text(status, style: style)
                  : StatusPill(label: status, color: statusColor!),
            ),
          ),
          if (!header)
            const SizedBox(
              width: 32,
              child: Icon(Icons.more_horiz_rounded, size: 18),
            ),
          if (header) const SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.reference,
    required this.product,
    required this.quantity,
    required this.time,
    required this.incoming,
  });

  final String reference;
  final String product;
  final String quantity;
  final String time;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final color = incoming ? AppColors.success : AppColors.error;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(
            incoming ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: color,
            size: 17,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$reference · $time',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Text(
          quantity,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RestockRow extends StatelessWidget {
  const _RestockRow({
    required this.product,
    required this.suggested,
    required this.urgency,
    required this.color,
  });

  final String product;
  final String suggested;
  final String urgency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                suggested,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        StatusPill(label: urgency, color: color),
      ],
    );
  }
}
