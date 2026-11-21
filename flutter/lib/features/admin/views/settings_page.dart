import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:client/features/admin/viewmodels/catalogue_lists_viewmodel.dart';
import 'package:client/features/admin/viewmodels/storage_locations_viewmodel.dart';
import 'package:client/features/admin/views/storage_locations_page.dart';
import 'package:client/features/admin/widgets/catalogue_lists_panel.dart';
import 'package:client/features/admin/widgets/catalogue_masters_panel.dart';
import 'package:client/features/admin/widgets/receipt_numbering_settings_panel.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/system_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Store details shown on the admin Settings screen (decisions D-03, D10).
///
/// Inlined here rather than read from `AdminMockData`: a "mock data" bag holding
/// the store's own name and contact details made the one screen of real store
/// facts read as fake. These three constants stay read-only because no endpoint
/// carries them yet; the sales settings above them DO come from the server
/// (Phase 4 B1, `GET/PATCH /api/v1/store-settings/`).
///
/// The stocker's `InventorySettingsPage` shows the same literals, because both
/// screens describe the same store.
const _storeName = 'QB Hardware & Construction Supplies';
const _storeEmail = 'contact@qbhardware.com';
const _storePhone = '+63 912 345 6789';

/// Where a section stops growing on a wide window: label/value pairs read
/// better in a column than across 1200 px.
const double _readingWidth = 720;

/// Width of the side menu on a wide window.
const double _menuWidth = 220;

/// Below this the side menu becomes a row of tabs above the section.
const double _sideMenuBreakpoint = 760;

/// The sections of Settings, in side-menu order (owner 2026-11-18: side tabs on
/// the left, like GitHub's settings).
enum SettingsSection {
  sales(
    'Sales & tax',
    Icons.receipt_long_outlined,
    'VAT on receipts and the most a cashier may discount.',
    'Store',
  ),
  store(
    'Store information',
    Icons.storefront_outlined,
    'The name and contact details printed for this store.',
    null,
  ),
  locations(
    'Storage locations',
    Icons.warehouse_outlined,
    'Where the shop keeps goods, and the pick-up point the till prints. '
        'Deactivate a place instead of deleting it; history keeps its name.',
    null,
  ),
  documents(
    'Receipts & numbering',
    Icons.tag_rounded,
    'Document series prefixes for official receipts, sales, deliveries, '
        'purchase orders, and receipt print templates.',
    null,
  ),
  categories(
    'Categories',
    Icons.category_outlined,
    'Product categories every screen picks from. Archive to hide one from the '
        'pickers and keep its history; delete only what was never used.',
    'Catalogue',
  ),
  suppliers(
    'Suppliers',
    Icons.local_shipping_outlined,
    'Suppliers purchase orders are raised to. Archive to hide one from the '
        'pickers and keep its history; delete only what was never used.',
    null,
  ),
  brands(
    'Brands',
    Icons.sell_outlined,
    'Product brands shared across inventory, receiving, and POS product cards.',
    null,
  ),
  units(
    'Units (UOM)',
    Icons.straighten_rounded,
    'Standard measurement units (PC, BAG, SHEET, KG, M) and whole-unit rules.',
    null,
  ),
  system(
    'System settings',
    Icons.palette_outlined,
    'Customize the theme, accent palette, sidebar finish, and display comfort '
        'for this device.',
    'System',
  );

  const SettingsSection(this.label, this.icon, this.description, this.group);
  final String label;
  final IconData icon;
  final String description;

  /// The heading this section starts, if it starts one.
  final String? group;
}

/// The admin Settings screen: the store's VAT and discount rules (server-owned)
/// above the store's contact details (constants).
///
/// The server is the trust boundary: the fields are collected here, but the
/// percent rules are re-checked before the request and the server's own refusal
/// is what the banner shows. A non-admin who reaches this page reads the values
/// and gets no fields and no Save.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.viewmodel,
    this.catalogueLists,
    this.catalogueMasters,
    this.storageLocations,
    this.initialSection = SettingsSection.sales,
  });

  /// The storage-locations tab's data, injected by tests.
  final StorageLocationsViewmodel? storageLocations;

  /// The brands & units tabs' data, injected by tests.
  final CatalogueMastersViewmodel? catalogueMasters;

  /// The section open when the page opens.
  final SettingsSection initialSection;

  /// Injected by tests so the load and save paths run without a server.
  /// Production reads the app-scoped instance registered in `main.dart`, which
  /// is also what the till reads (Phase 4 F4).
  final StoreSettingsViewmodel? viewmodel;

  /// The categories & suppliers panel's data, injected by tests (it reads the
  /// server otherwise).
  final CatalogueListsViewmodel? catalogueLists;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _vatRateLabel = 'VAT rate (%)';
  static const _discountCapLabel = 'Discount cap (%)';
  static const _shiftDiscountCapLabel = 'Shift discount limit (%)';
  static const _shiftDiscountCapHelper =
      'Total discounts a cashier can give in one shift before a manager must '
      'approve. Leave empty for no limit.';

  late final StoreSettingsViewmodel _settings;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _vatRate = TextEditingController();
  final TextEditingController _discountCap = TextEditingController();
  final TextEditingController _shiftDiscountCap = TextEditingController();
  bool _vatRegistered = StoreSettings.defaults.vatRegistered;
  late SettingsSection _section = widget.initialSection;

  @override
  void initState() {
    super.initState();
    _settings = widget.viewmodel ?? context.read<StoreSettingsViewmodel>();
    _seedFields();
    _load();
  }

  @override
  void dispose() {
    _vatRate.dispose();
    _discountCap.dispose();
    _shiftDiscountCap.dispose();
    for (final controller in _feeValues.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Copies the current values into the fields. Called on open and after the
  /// load answers, never while someone is typing.
  /// Per-method fee controls (owner ruling). One row per method the server
  /// allows a fee on; a fresh shop starts switched OFF with 0.00, never with an
  /// invented rate.
  final Map<String, TextEditingController> _feeValues = {
    for (final method in TenderFee.feeableMethods)
      method: TextEditingController(text: '0.00'),
  };
  final Map<String, String> _feeKinds = {};
  final Map<String, bool> _feeActive = {};

  void _seedFields() {
    _vatRegistered = _settings.vatRegistered;
    _vatRate.text = _settings.vatRate.toStringAsFixed(2);
    _discountCap.text = _settings.discountCapPercent.toStringAsFixed(2);
    final shiftCap = _settings.shiftDiscountCapPercent;
    _shiftDiscountCap.text = shiftCap?.toStringAsFixed(2) ?? '';
    for (final method in TenderFee.feeableMethods) {
      TenderFee? stored;
      for (final fee in _settings.settings.tenderFees) {
        if (fee.method == method) stored = fee;
      }
      _feeKinds[method] = stored?.kind ?? TenderFee.kindPercent;
      _feeActive[method] = stored?.isActive ?? false;
      _feeValues[method]!.text = (stored?.value ?? 0).toStringAsFixed(2);
    }
  }

  Future<void> _load() async {
    await _settings.load();
    if (!mounted) return;
    setState(_seedFields);
  }

  double _percent(String raw) => double.parse(raw.trim());

  /// The optional shift cap: an empty field means no limit, which goes to the
  /// server as an explicit null.
  double? _optionalPercent(String raw) =>
      raw.trim().isEmpty ? null : _percent(raw);

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final saved = await _settings.save(
      vatRegistered: _vatRegistered,
      vatRate: _percent(_vatRate.text),
      discountCapPercent: _percent(_discountCap.text),
      shiftDiscountCapPercent: _optionalPercent(_shiftDiscountCap.text),
      // The WHOLE list is sent: a method left out ends up with no fee on the
      // server, so an unchecked row must still be named as switched off.
      tenderFees: [
        for (final method in TenderFee.feeableMethods)
          TenderFee(
            method: method,
            kind: _feeKinds[method] ?? TenderFee.kindPercent,
            value: double.tryParse(_feeValues[method]!.text.trim()) ?? 0,
            isActive: _feeActive[method] ?? false,
          ),
      ],
    );
    if (!mounted || !saved) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Store settings saved.')));
  }

  @override
  Widget build(BuildContext context) {
    // Holds Admin, not "is working in Admin": a merged Admin + Cashier account
    // keeps the form (Phase 2 F3).
    final isAdmin = context.watch<AuthViewmodel>().hasArea('admin');
    return AdminSkeletonLayout(
      title: 'Settings',
      subtitle: 'Store details this system keeps.',
      // 6, not 7: Requisitions left the sidebar (decision 01).
      selectedNavigationIndex: AppDestinations.indexOf(
        'admin.settings',
        AppAreas.admin,
      ),
      child: LayoutBuilder(
        builder: (context, slot) {
          final wide = slot.maxWidth >= _sideMenuBreakpoint;
          final menu = _SettingsMenu(
            selected: _section,
            vertical: wide,
            onSelect: (section) => setState(() => _section = section),
          );
          final body = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _readingWidth),
            child: _sectionBody(context, isAdmin),
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

  /// The open section: its heading, a rule, then its content.
  Widget _sectionBody(BuildContext context, bool isAdmin) {
    final p = AppPalette.of(context);
    final section = _section;
    final content = switch (section) {
      SettingsSection.sales => ListenableBuilder(
        listenable: _settings,
        builder: (context, _) =>
            AppPanel(child: isAdmin ? _form(context) : _readOnly(context)),
      ),
      SettingsSection.store => const _StoreInformationCard(),
      // Owner 2026-11-18: moved here from its own sidebar row.
      SettingsSection.locations => StorageLocationsPanel(
        key: const ValueKey('settings-storage-locations'),
        viewmodel: widget.storageLocations,
      ),
      SettingsSection.documents => ReceiptNumberingSettingsPanel(
        key: const ValueKey('settings-documents'),
        canEdit: isAdmin,
      ),
      // Owner 2026-11-18: the shop-wide categories and suppliers every other
      // screen picks from.
      SettingsSection.categories => CatalogueListsPanel(
        key: const ValueKey('settings-categories'),
        only: CatalogueList.categories,
        canDelete: isAdmin,
        viewmodel: widget.catalogueLists,
      ),
      SettingsSection.suppliers => CatalogueListsPanel(
        key: const ValueKey('settings-suppliers'),
        only: CatalogueList.suppliers,
        canDelete: isAdmin,
        viewmodel: widget.catalogueLists,
      ),
      SettingsSection.brands => CatalogueMastersPanel(
        key: const ValueKey('settings-brands'),
        kind: CatalogueMasterKind.brands,
        canEdit: isAdmin,
        viewmodel: widget.catalogueMasters,
      ),
      SettingsSection.units => CatalogueMastersPanel(
        key: const ValueKey('settings-units'),
        kind: CatalogueMasterKind.units,
        canEdit: isAdmin,
        viewmodel: widget.catalogueMasters,
      ),
      SettingsSection.system => const SystemSettingsPanel(
        key: ValueKey('settings-system'),
      ),
    };
    return Column(
      key: ValueKey('settings-section-${section.name}'),
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

  Widget _form(BuildContext context) {
    final loadError = _settings.loadError;
    final saveError = _settings.saveError;
    final isSaving = _settings.isSaving;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loadError != null) ...[
            ErrorBanner(message: loadError, onRetry: _load),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (saveError != null) ...[
            ErrorBanner(message: saveError),
            const SizedBox(height: AppSpacing.lg),
          ],
          // A plain Switch row, not a SwitchListTile: the tile paints its
          // background on the nearest Material and asserts under AppPanel's
          // painted DecoratedBox.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VAT registered',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppPalette.of(context).textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Break out VAT on receipts and reports.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _vatRegistered,
                onChanged: isSaving
                    ? null
                    : (value) {
                        setState(() => _vatRegistered = value);
                        _settings.clearSaveError();
                      },
              ),
            ],
          ),
          if (_vatRegistered) ...[
            const SizedBox(height: AppSpacing.md),
            _PercentField(
              label: _vatRateLabel,
              controller: _vatRate,
              enabled: !isSaving,
              onChanged: _settings.clearSaveError,
            ),
            const SizedBox(height: AppSpacing.md),
            // Prices are entered VAT-inclusive, so a reader must not add the
            // rate on top of a shelf price.
            const InfoBanner(
              message: 'Prices on the shelf already include VAT.',
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _PercentField(
            label: _discountCapLabel,
            controller: _discountCap,
            enabled: !isSaving,
            onChanged: _settings.clearSaveError,
          ),
          const SizedBox(height: AppSpacing.md),
          // Optional on purpose: the per-sale cap above always applies, and an
          // empty field means the shop sets no limit across a shift.
          _PercentField(
            label: _shiftDiscountCapLabel,
            controller: _shiftDiscountCap,
            enabled: !isSaving,
            onChanged: _settings.clearSaveError,
            helperText: _shiftDiscountCapHelper,
            optional: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Payment method fees',
            style: TextStyle(
              fontSize: 15,
              color: AppPalette.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Charged on top of the bill for taking a payment the bank bills the '
            'shop for. Off by default. Not VAT.',
            style: TextStyle(
              fontSize: 12,
              color: AppPalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final method in TenderFee.feeableMethods) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      TenderFee(
                        method: method,
                        kind: TenderFee.kindPercent,
                        value: 0,
                      ).label,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppPalette.of(context).textPrimary,
                      ),
                    ),
                  ),
                  Switch(
                    value: _feeActive[method] ?? false,
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setState(() => _feeActive[method] = value);
                            _settings.clearSaveError();
                          },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  DropdownButton<String>(
                    value: _feeKinds[method] ?? TenderFee.kindPercent,
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setState(
                              () => _feeKinds[method] =
                                  value ?? TenderFee.kindPercent,
                            );
                            _settings.clearSaveError();
                          },
                    items: const [
                      DropdownMenuItem(
                        value: TenderFee.kindPercent,
                        child: Text('Percent'),
                      ),
                      DropdownMenuItem(
                        value: TenderFee.kindAmount,
                        child: Text('Peso amount'),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _feeValues[method],
                      enabled: !isSaving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => _settings.clearSaveError(),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText:
                            (_feeKinds[method] ?? TenderFee.kindPercent) ==
                                TenderFee.kindAmount
                            ? '₱ '
                            : null,
                        suffixText:
                            (_feeKinds[method] ?? TenderFee.kindPercent) ==
                                TenderFee.kindPercent
                            ? '%'
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: isSaving ? null : _save,
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save settings'),
            ),
          ),
        ],
      ),
    );
  }

  /// What a non-admin reads if this page is ever reachable for them: the values,
  /// no way to change them, and a sentence saying who can.
  Widget _readOnly(BuildContext context) {
    final loadError = _settings.loadError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loadError != null) ...[
          ErrorBanner(message: loadError, onRetry: _load),
          const SizedBox(height: AppSpacing.lg),
        ],
        _Field(label: 'VAT registered', value: _vatRegistered ? 'Yes' : 'No'),
        const SizedBox(height: AppSpacing.md),
        if (_vatRegistered) ...[
          _Field(
            label: _vatRateLabel,
            value: '${_settings.vatRate.toStringAsFixed(2)}%',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _Field(
          label: _discountCapLabel,
          value: '${_settings.discountCapPercent.toStringAsFixed(2)}%',
        ),
        const SizedBox(height: AppSpacing.md),
        _Field(
          label: _shiftDiscountCapLabel,
          value: switch (_settings.shiftDiscountCapPercent) {
            final cap? => '${cap.toStringAsFixed(2)}%',
            null => 'No limit',
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        const InfoBanner(message: 'Only an Admin can change these settings.'),
      ],
    );
  }
}

/// One percent input with the shared rule as its validator. With [optional]
/// set, an empty field is allowed and means "not set"; when it is not, an empty
/// field fails the same rule as any other non-number.
class _PercentField extends StatelessWidget {
  const _PercentField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.helperText,
    this.optional = false,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final String? helperText;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 3,
      ),
      validator: (value) {
        final raw = value ?? '';
        if (optional && raw.trim().isEmpty) return null;
        return StoreSettings.percentError(raw);
      },
      onChanged: (_) => onChanged(),
    );
  }
}

/// The three store facts and the reason they cannot be edited.
class _StoreInformationCard extends StatelessWidget {
  const _StoreInformationCard();

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Field(label: 'Store name', value: _storeName),
          const SizedBox(height: AppSpacing.lg),
          const _Field(label: 'Contact email', value: _storeEmail),
          const SizedBox(height: AppSpacing.lg),
          const _Field(label: 'Contact number', value: _storePhone),
          const SizedBox(height: AppSpacing.lg),
          // Read-only on purpose: a field the admin could type in, or a Save
          // button with nothing behind it, would promise an editing path the
          // system does not have.
          Text(
            'Editing store details is not available yet.',
            style: TextStyle(
              fontSize: 12,
              color: AppPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled store fact. The label sits above the value so a long store name
/// wraps inside the card instead of shortening next to a fixed label column.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: TextStyle(fontSize: 15, color: p.textPrimary)),
      ],
    );
  }
}

/// GitHub-style settings menu: grouped items on the left, the open one marked
/// with an accent bar. On a narrow window it is one scrolling row of tabs.
class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({
    required this.selected,
    required this.vertical,
    required this.onSelect,
  });

  final SettingsSection selected;
  final bool vertical;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final items = [
      for (final section in SettingsSection.values)
        _SettingsMenuItem(
          section: section,
          selected: section == selected,
          onTap: () => onSelect(section),
        ),
    ];
    if (!vertical) {
      return SingleChildScrollView(
        key: const ValueKey('settings-menu'),
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
      key: const ValueKey('settings-menu'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, section) in SettingsSection.values.indexed) ...[
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

class _SettingsMenuItem extends StatelessWidget {
  const _SettingsMenuItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      key: ValueKey('settings-menu-${section.name}'),
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
              // The open item's marker, like GitHub's left bar.
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
              // Not Flexible: the narrow menu is a sideways-scrolling row,
              // where a flex child has no width to share.
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
