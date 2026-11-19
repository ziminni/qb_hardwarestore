import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

enum _AccessLevel {
  full('Full'),
  manage('Manage'),
  view('View'),
  own('Own'),
  none('—');

  const _AccessLevel(this.label);
  final String label;
}

class _PermissionRow {
  const _PermissionRow({
    required this.capability,
    required this.module,
    required this.admin,
    required this.storeManager,
    required this.stockManager,
    required this.cashier,
    required this.bodega,
  });

  final String capability;
  final String module;
  final _AccessLevel admin;
  final _AccessLevel storeManager;
  final _AccessLevel stockManager;
  final _AccessLevel cashier;
  final _AccessLevel bodega;
}

const List<String> _modules = [
  'All modules',
  'POS & Till',
  'Sales & Finance',
  'Inventory',
  'Bodega',
  'Administration',
];

const List<_PermissionRow> _matrix = [
  // POS & Till
  _PermissionRow(
    capability: 'Process walk-in & project sales',
    module: 'POS & Till',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.view,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.full,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Open & close cash shifts',
    module: 'POS & Till',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.view,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.own,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Hold & resume carts, process returns',
    module: 'POS & Till',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.view,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.full,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Receipt printer & till preferences',
    module: 'POS & Till',
    admin: _AccessLevel.none,
    storeManager: _AccessLevel.none,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.full,
    bodega: _AccessLevel.none,
  ),

  // Sales & Finance
  _PermissionRow(
    capability: 'Quotations, sales orders & transactions',
    module: 'Sales & Finance',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.full,
    stockManager: _AccessLevel.view,
    cashier: _AccessLevel.own,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Project requests review queue',
    module: 'Sales & Finance',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.full,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Customer receivables & cheque queue',
    module: 'Sales & Finance',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.full,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.manage,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Supplier payables & payments',
    module: 'Sales & Finance',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.full,
    stockManager: _AccessLevel.full,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Sales & financial reports',
    module: 'Sales & Finance',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.full,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.none,
  ),

  // Inventory
  _PermissionRow(
    capability: 'Products, variants, stock & receiving',
    module: 'Inventory',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.view,
    stockManager: _AccessLevel.full,
    cashier: _AccessLevel.view,
    bodega: _AccessLevel.view,
  ),
  _PermissionRow(
    capability: 'Purchase orders, adjustments & transfers',
    module: 'Inventory',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.manage,
    stockManager: _AccessLevel.full,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Deliveries schedule & Excel import/export',
    module: 'Inventory',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.manage,
    stockManager: _AccessLevel.full,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.view,
  ),

  // Bodega
  _PermissionRow(
    capability: 'Release pick-ups & verify deliveries (QR)',
    module: 'Bodega',
    admin: _AccessLevel.view,
    storeManager: _AccessLevel.none,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.full,
  ),

  // Administration
  _PermissionRow(
    capability: 'Create staff accounts & assign Admin role',
    module: 'Administration',
    admin: _AccessLevel.full,
    storeManager: _AccessLevel.none,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Deactivate / change non-admin staff roles',
    module: 'Administration',
    admin: _AccessLevel.full,
    storeManager: _AccessLevel.manage,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Store VAT, discount cap & catalogue lists',
    module: 'Administration',
    admin: _AccessLevel.full,
    storeManager: _AccessLevel.none,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.none,
  ),
  _PermissionRow(
    capability: 'Audit logs, Backup & restore, Security',
    module: 'Administration',
    admin: _AccessLevel.full,
    storeManager: _AccessLevel.none,
    stockManager: _AccessLevel.none,
    cashier: _AccessLevel.none,
    bodega: _AccessLevel.none,
  ),
];

/// Opens the Roles & Permissions reference matrix from User Management.
Future<void> showRolesPermissionsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const RolesPermissionsDialog(),
  );
}

/// Read-only governance reference showing what each Queen Builders role can
/// view, manage, or approve, plus server-enforced guardrails.
class RolesPermissionsDialog extends StatefulWidget {
  const RolesPermissionsDialog({super.key});

  @override
  State<RolesPermissionsDialog> createState() => _RolesPermissionsDialogState();
}

class _RolesPermissionsDialogState extends State<RolesPermissionsDialog> {
  String _selectedModule = 'All modules';

  List<_PermissionRow> get _visibleRows => _selectedModule == 'All modules'
      ? _matrix
      : _matrix.where((r) => r.module == _selectedModule).toList();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final rows = _visibleRows;

    return AppDialog(
      icon: Icons.verified_user_outlined,
      title: 'Roles & permissions',
      subtitle: 'What each workspace role can view, manage, or approve.',
      width: 860,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final module in _modules)
                ChoiceChip(
                  label: Text(module),
                  selected: _selectedModule == module,
                  backgroundColor: p.surfaceSunken,
                  selectedColor: p.selected,
                  checkmarkColor: p.accentInk,
                  side: BorderSide(
                    color: _selectedModule == module ? p.accent : p.border,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _selectedModule == module
                        ? p.accentInk
                        : p.textPrimary,
                  ),
                  onSelected: (_) => setState(() => _selectedModule = module),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Legend:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
              const _LevelChip(_AccessLevel.full),
              Text(
                'Full control',
                style: TextStyle(fontSize: 11.5, color: p.textSecondary),
              ),
              const _LevelChip(_AccessLevel.manage),
              Text(
                'Scoped actions',
                style: TextStyle(fontSize: 11.5, color: p.textSecondary),
              ),
              const _LevelChip(_AccessLevel.own),
              Text(
                'Own shifts/records',
                style: TextStyle(fontSize: 11.5, color: p.textSecondary),
              ),
              const _LevelChip(_AccessLevel.view),
              Text(
                'Read only',
                style: TextStyle(fontSize: 11.5, color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 740),
              child: Container(
                decoration: BoxDecoration(
                  color: p.cardBackground,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(color: p.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      color: p.tableHeader,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 260,
                            child: Text(
                              'CAPABILITY',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                          for (final role in const [
                            'Admin',
                            'Store Mgr',
                            'Stock Mgr',
                            'Cashier',
                            'Bodega',
                          ])
                            SizedBox(
                              width: 96,
                              child: Text(
                                role.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: p.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < rows.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: p.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 260,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rows[i].capability,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  if (_selectedModule == 'All modules')
                                    Text(
                                      rows[i].module,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: p.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 96,
                              child: Center(child: _LevelChip(rows[i].admin)),
                            ),
                            SizedBox(
                              width: 96,
                              child: Center(
                                child: _LevelChip(rows[i].storeManager),
                              ),
                            ),
                            SizedBox(
                              width: 96,
                              child: Center(
                                child: _LevelChip(rows[i].stockManager),
                              ),
                            ),
                            SizedBox(
                              width: 96,
                              child: Center(child: _LevelChip(rows[i].cashier)),
                            ),
                            SizedBox(
                              width: 96,
                              child: Center(child: _LevelChip(rows[i].bodega)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const DialogSectionLabel('Server-enforced guardrails'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _GuardrailBullet(
                  'Last-admin protection: the last active Admin account '
                  'cannot be deactivated or stripped of Admin authority.',
                ),
                SizedBox(height: 6),
                _GuardrailBullet(
                  'Manager boundary: Store Managers can update non-admin '
                  'staff roles and status, but cannot create accounts or '
                  'modify Admin accounts.',
                ),
                SizedBox(height: 6),
                _GuardrailBullet(
                  'Discount ceiling: Cashiers cannot exceed the store '
                  'discount cap configured in Admin Settings without manager '
                  'approval.',
                ),
                SizedBox(height: 6),
                _GuardrailBullet(
                  'Bodega separation: Bodega Checkers confirm pick-ups and '
                  'deliveries only—stock levels change exclusively through '
                  'Receiving, POS sales, and approved adjustments.',
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip(this.level);

  final _AccessLevel level;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (level == _AccessLevel.none) {
      return Text(
        '—',
        style: TextStyle(fontSize: 13, color: p.textSecondary),
      );
    }

    final (Color bg, Color fg) = switch (level) {
      _AccessLevel.full => (
        p.isDark
            ? AppColors.success.withValues(alpha: 0.18)
            : AppColors.successTint,
        p.isDark ? const Color(0xFF86EFAC) : AppColors.successText,
      ),
      _AccessLevel.manage => (p.selected, p.accentInk),
      _AccessLevel.own => (
        p.isDark
            ? AppColors.warning.withValues(alpha: 0.18)
            : AppColors.warningTint,
        p.isDark ? const Color(0xFFFCD34D) : AppColors.warningText,
      ),
      _AccessLevel.view => (p.surfaceSunken, p.textSecondary),
      _AccessLevel.none => (Colors.transparent, p.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: level == _AccessLevel.view ? Border.all(color: p.border) : null,
      ),
      child: Text(
        level.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _GuardrailBullet extends StatelessWidget {
  const _GuardrailBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: p.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: p.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
