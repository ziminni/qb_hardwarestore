import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/printing/raw_printer.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/controllers/pos_lock_settings_controller.dart';
import 'package:client/features/pos/controllers/pos_till_settings_controller.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/widgets/receipt_printer_panel.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/system_settings_panel.dart';
import 'package:flutter/material.dart';

/// Width of the side menu on a wide window, as the Admin's Settings.
const double _menuWidth = 220;

/// Below this the side menu becomes a row of tabs above the section.
const double _sideMenuBreakpoint = 760;

/// The widest a section's content grows, as the Admin's Settings.
const double _readingWidth = 720;

/// The till's Settings sections, in side-menu order. The same shape as the
/// Admin's `SettingsSection`, so the two screens read alike (owner
/// 2026-11-19).
enum PosSettingsSection {
  receiptPrinter(
    'Receipt printer',
    Icons.print_outlined,
    'The thermal printer on this computer that receipts and delivery slips '
        'print to. Saved on this computer only.',
    'Printing',
  ),
  checkoutAndRegister(
    'Checkout & till',
    Icons.point_of_sale_outlined,
    'Receipt auto-printing, cash drawer kick, barcode scanner behavior, and '
        'default sale preferences on this counter computer.',
    'Till & Register',
  ),
  security(
    'Security & lock',
    Icons.lock_outline_rounded,
    'Automatically lock the till screen after inactivity or after a sale. '
        'Saved on this computer only.',
    'Security',
  ),
  system(
    'System settings',
    Icons.palette_outlined,
    'Customize the theme, accent palette, sidebar finish, and display comfort '
        'for this till computer.',
    'System',
  );

  const PosSettingsSection(this.label, this.icon, this.description, this.group);
  final String label;
  final IconData icon;
  final String description;

  /// The heading this section starts, if it starts one.
  final String? group;
}

/// The till's Settings tab, laid out like the Admin's Settings: side tabs on
/// the left (grouped, the open one marked in gold), the open section on the
/// right with its heading, a one-line description and a rule.
///
/// The cashier's, not the Admin's (owner 2026-11-18): the printer is plugged
/// into the counter computer. Appended last in the till's menu, so no earlier
/// tab moves.
class PosSettingsPage extends StatefulWidget {
  const PosSettingsPage({
    super.key,
    this.raw,
    this.lockSettings,
    this.tillSettings,
  });

  /// Injected by tests; the app talks to this computer's print system.
  final RawPrinter? raw;

  /// Injected by tests; defaults to [PosLockSettingsController.instance].
  final PosLockSettingsController? lockSettings;

  /// Injected by tests; defaults to [PosTillSettingsController.instance].
  final PosTillSettingsController? tillSettings;

  @override
  State<PosSettingsPage> createState() => _PosSettingsPageState();
}

class _PosSettingsPageState extends State<PosSettingsPage> {
  PosSettingsSection _section = PosSettingsSection.receiptPrinter;

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Settings',
      subtitle: 'Settings for this till.',
      selectedNavigationIndex: AppDestinations.indexOf(
        'pos.settings',
        AppAreas.pos,
      ),
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      lockSettings: widget.lockSettings,
      child: LayoutBuilder(
        builder: (context, slot) {
          final wide = slot.maxWidth >= _sideMenuBreakpoint;
          final menu = _PosSettingsMenu(
            selected: _section,
            vertical: wide,
            onSelect: (section) => setState(() => _section = section),
          );
          final body = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _readingWidth),
            child: _sectionBody(),
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                menu,
                const SizedBox(height: AppSpacing.lg),
                body,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: _menuWidth, child: menu),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Align(alignment: Alignment.topLeft, child: body),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The open section: its heading, its description, a rule, its content.
  Widget _sectionBody() {
    final p = AppPalette.of(context);
    final section = _section;
    final content = switch (section) {
      PosSettingsSection.receiptPrinter => ReceiptPrinterPanel(
        key: const ValueKey('pos-settings-receipt-printer'),
        raw: widget.raw,
      ),
      PosSettingsSection.checkoutAndRegister => _PosTillSettingsPanel(
        key: const ValueKey('pos-settings-checkout-register'),
        controller: widget.tillSettings,
      ),
      PosSettingsSection.security => _PosAutoLockPanel(
        key: const ValueKey('pos-settings-security'),
        controller: widget.lockSettings,
      ),
      PosSettingsSection.system => const SystemSettingsPanel(
        key: ValueKey('pos-settings-system'),
      ),
    };
    return Column(
      key: ValueKey('pos-settings-section-${section.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          section.label,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(section.description, style: TextStyle(color: p.textSecondary)),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.lg),
        content,
      ],
    );
  }
}

/// The side menu: grouped items on a wide window, one sideways-scrolling row
/// on a narrow one. Drawn like the Admin's Settings menu.
class _PosSettingsMenu extends StatelessWidget {
  const _PosSettingsMenu({
    required this.selected,
    required this.vertical,
    required this.onSelect,
  });

  final PosSettingsSection selected;
  final bool vertical;
  final ValueChanged<PosSettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final items = [
      for (final section in PosSettingsSection.values)
        _PosSettingsMenuItem(
          section: section,
          selected: section == selected,
          onTap: () => onSelect(section),
        ),
    ];
    if (!vertical) {
      return SingleChildScrollView(
        key: const ValueKey('pos-settings-menu'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in items) ...[
              item,
              const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
      );
    }
    return Column(
      key: const ValueKey('pos-settings-menu'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, section) in PosSettingsSection.values.indexed) ...[
          if (section.group != null) ...[
            if (index > 0) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                section.group!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
            ),
          ],
          items[index],
          const SizedBox(height: 2),
        ],
      ],
    );
  }
}

class _PosSettingsMenuItem extends StatelessWidget {
  const _PosSettingsMenuItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final PosSettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      key: ValueKey('pos-settings-menu-${section.name}'),
      color: selected ? p.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          selected: selected,
          button: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The open item's marker, the Admin menu's accent left bar.
              Container(
                width: 3,
                height: 36,
                color: selected ? p.accent : Colors.transparent,
              ),
              const SizedBox(width: AppSpacing.md - 3),
              Icon(
                section.icon,
                size: 18,
                color: selected ? p.textPrimary : p.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  section.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? p.textPrimary : p.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosAutoLockPanel extends StatefulWidget {
  const _PosAutoLockPanel({super.key, this.controller});

  final PosLockSettingsController? controller;

  @override
  State<_PosAutoLockPanel> createState() => _PosAutoLockPanelState();
}

class _PosAutoLockPanelState extends State<_PosAutoLockPanel> {
  late PosLockSettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PosLockSettingsController.instance;
    _controller.load();
  }

  @override
  void didUpdateWidget(covariant _PosAutoLockPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.controller ?? PosLockSettingsController.instance;
    if (!identical(next, _controller)) {
      _controller = next;
      _controller.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final current = _controller.option;
        return AppPanel(
          title: 'Automatic lock',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lock the cashier till screen automatically after no pointer or '
                'scroll activity for the selected duration.',
                style: TextStyle(color: p.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: DropdownButtonFormField<PosAutoLockOption>(
                  key: const ValueKey('pos-auto-lock-dropdown'),
                  initialValue: current,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Auto-lock after',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  items: [
                    for (final option in PosAutoLockOption.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (selected) {
                    if (selected != null) {
                      _controller.setOption(selected);
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    SwitchListTile(
                      key: const ValueKey('pos-lock-shortcut-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Quick-lock keyboard shortcut'),
                      subtitle: const Text(
                        'Press Ctrl+L or Cmd+L to lock immediately',
                      ),
                      value: _controller.lockShortcutEnabled,
                      onChanged: _controller.setLockShortcutEnabled,
                    ),
                    SwitchListTile(
                      key: const ValueKey('pos-lock-after-sale-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Lock after completing a sale'),
                      subtitle: const Text(
                        'Require password after each checkout on shared counter '
                        'PCs',
                      ),
                      value: _controller.lockAfterSale,
                      onChanged: _controller.setLockAfterSale,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PosTillSettingsPanel extends StatefulWidget {
  const _PosTillSettingsPanel({super.key, this.controller});

  final PosTillSettingsController? controller;

  @override
  State<_PosTillSettingsPanel> createState() => _PosTillSettingsPanelState();
}

class _PosTillSettingsPanelState extends State<_PosTillSettingsPanel> {
  late PosTillSettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PosTillSettingsController.instance;
    _controller.load();
  }

  @override
  void didUpdateWidget(covariant _PosTillSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.controller ?? PosTillSettingsController.instance;
    if (!identical(next, _controller)) {
      _controller = next;
      _controller.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPanel(
              title: 'Checkout & printing',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose how receipts and the cash drawer behave when a sale '
                    'is completed at this till.',
                    style: TextStyle(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      SizedBox(
                        width: 280,
                        child: DropdownButtonFormField<PosAutoPrintMode>(
                          key: const ValueKey('pos-auto-print-dropdown'),
                          initialValue: _controller.autoPrintMode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Auto-print receipt',
                            prefixIcon: Icon(Icons.receipt_long_outlined),
                          ),
                          items: [
                            for (final mode in PosAutoPrintMode.values)
                              DropdownMenuItem(
                                value: mode,
                                child: Text(mode.label),
                              ),
                          ],
                          onChanged: (selected) {
                            if (selected != null) {
                              _controller.setAutoPrintMode(selected);
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<int>(
                          key: const ValueKey('pos-receipt-copies-dropdown'),
                          initialValue: _controller.receiptCopies,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Receipt copies',
                            prefixIcon: Icon(Icons.copy_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1 copy')),
                            DropdownMenuItem(value: 2, child: Text('2 copies')),
                          ],
                          onChanged: (selected) {
                            if (selected != null) {
                              _controller.setReceiptCopies(selected);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const ValueKey('pos-open-cash-drawer-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Auto-open cash drawer on cash payment',
                      ),
                      subtitle: const Text(
                        'Send a drawer-kick pulse to the thermal printer on '
                        'cash tenders',
                      ),
                      value: _controller.autoOpenCashDrawer,
                      onChanged: _controller.setAutoOpenCashDrawer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              title: 'Register & scanner',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customize barcode scanning, audio cues, and default sale '
                    'mode on New transaction.',
                    style: TextStyle(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: DropdownButtonFormField<PosDefaultFulfillment>(
                      key: const ValueKey('pos-default-fulfillment-dropdown'),
                      initialValue: _controller.defaultFulfillment,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Default sale type',
                        prefixIcon: Icon(Icons.local_shipping_outlined),
                      ),
                      items: [
                        for (final mode in PosDefaultFulfillment.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                      ],
                      onChanged: (selected) {
                        if (selected != null) {
                          _controller.setDefaultFulfillment(selected);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        SwitchListTile(
                          key: const ValueKey('pos-auto-add-scan-switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Auto-add 1 unit on barcode scan'),
                          subtitle: const Text(
                            'Add exact barcode matches straight to the cart',
                          ),
                          value: _controller.autoAddOnScan,
                          onChanged: _controller.setAutoAddOnScan,
                        ),
                        SwitchListTile(
                          key: const ValueKey('pos-auto-refocus-switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Auto-refocus search after sale'),
                          subtitle: const Text(
                            'Keep the product/barcode box ready for the next '
                            'customer',
                          ),
                          value: _controller.autoRefocusSearch,
                          onChanged: _controller.setAutoRefocusSearch,
                        ),
                        SwitchListTile(
                          key: const ValueKey('pos-sound-feedback-switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Sound feedback'),
                          subtitle: const Text(
                            'Play a chime on scan or checkout and a tone on '
                            'errors',
                          ),
                          value: _controller.soundFeedback,
                          onChanged: _controller.setSoundFeedback,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
