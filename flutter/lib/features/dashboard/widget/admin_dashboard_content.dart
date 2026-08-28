import 'package:client/core/constants/app_colors.dart';
import 'package:client/features/dashboard/widget/dashboard_components.dart';
import 'package:flutter/material.dart';

class AdminDashboardContent extends StatelessWidget {
  const AdminDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    label: 'Today’s sales',
                    value: '₱84,250',
                    icon: Icons.payments_outlined,
                    color: AppColors.success,
                    change: '+12.4%',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const MetricCard(
                    label: 'Products in inventory',
                    value: '1,248',
                    icon: Icons.inventory_2_outlined,
                    color: AppColors.info,
                    change: '+18',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const MetricCard(
                    label: 'Low-stock items',
                    value: '23',
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    change: '+5',
                    changeIsPositive: false,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const MetricCard(
                    label: 'Active staff accounts',
                    value: '18',
                    icon: Icons.groups_2_outlined,
                    color: Color(0xFF8B5CF6),
                    change: '+2',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 900;
            final sales = DashboardPanel(
              title: 'Sales performance',
              subtitle: 'Revenue across the last seven days',
              action: TextButton(
                onPressed: () {},
                child: const Text('View report'),
              ),
              child: const SizedBox(height: 224, child: _SalesChart()),
            );
            final actions = DashboardPanel(
              title: 'Quick actions',
              subtitle: 'Common administrative tasks',
              child: Column(
                children: [
                  _QuickAction(
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'Create staff account',
                    color: const Color(0xFF8B5CF6),
                    onTap: () {},
                  ),
                  _QuickAction(
                    icon: Icons.add_box_outlined,
                    label: 'Add new product',
                    color: AppColors.info,
                    onTap: () {},
                  ),
                  _QuickAction(
                    icon: Icons.receipt_long_outlined,
                    label: 'Review requisitions',
                    color: AppColors.warning,
                    onTap: () {},
                  ),
                  _QuickAction(
                    icon: Icons.analytics_outlined,
                    label: 'Generate sales report',
                    color: AppColors.success,
                    onTap: () {},
                  ),
                ],
              ),
            );
            if (stacked) {
              return Column(
                children: [sales, const SizedBox(height: 20), actions],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: sales),
                const SizedBox(width: 20),
                Expanded(child: actions),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final recent = DashboardPanel(
              title: 'Recent activity',
              subtitle: 'Latest actions across the system',
              child: const Column(
                children: [
                  _ActivityRow(
                    icon: Icons.login_rounded,
                    color: AppColors.info,
                    title: 'Cashier Maria signed in',
                    subtitle: 'POS Terminal 02 · 8 minutes ago',
                  ),
                  Divider(height: 28),
                  _ActivityRow(
                    icon: Icons.inventory_2_outlined,
                    color: AppColors.success,
                    title: 'Stock receipt #SR-1042 completed',
                    subtitle: '124 items added · 24 minutes ago',
                  ),
                  Divider(height: 28),
                  _ActivityRow(
                    icon: Icons.price_change_outlined,
                    color: AppColors.warning,
                    title: 'Price updated for Portland Cement',
                    subtitle: 'Changed by Inventory Staff · 1 hour ago',
                  ),
                ],
              ),
            );
            final alerts = DashboardPanel(
              title: 'Inventory alerts',
              subtitle: 'Items requiring attention',
              action: TextButton(
                onPressed: () {},
                child: const Text('See all'),
              ),
              child: const Column(
                children: [
                  _AlertRow(
                    name: 'PVC Pipe 1/2"',
                    stock: '4 left',
                    color: AppColors.error,
                  ),
                  Divider(height: 27),
                  _AlertRow(
                    name: 'Marine Plywood',
                    stock: '8 left',
                    color: AppColors.warning,
                  ),
                  Divider(height: 27),
                  _AlertRow(
                    name: 'Masonry Nails 2"',
                    stock: '11 left',
                    color: AppColors.warning,
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 900) {
              return Column(
                children: [recent, const SizedBox(height: 20), alerts],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: recent),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: alerts),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart();

  @override
  Widget build(BuildContext context) {
    const values = [0.42, 0.58, 0.48, 0.78, 0.65, 0.92, 0.74];
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(values.length, (index) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: values[index],
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [AppColors.richGold, Color(0xFFE6D2AD)],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(7),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  labels[index],
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.name,
    required this.stock,
    required this.color,
  });

  final String name;
  final String stock;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        StatusPill(label: stock, color: color),
      ],
    );
  }
}
