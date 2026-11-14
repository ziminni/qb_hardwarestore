import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
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

/// Where the columns stop growing on a wide window: label/value pairs read
/// better in a column than across 1200 px.
const double _readingWidth = 640;

/// The admin Settings screen: the store's VAT and discount rules (server-owned)
/// above the store's contact details (constants).
///
/// The server is the trust boundary: the fields are collected here, but the
/// percent rules are re-checked before the request and the server's own refusal
/// is what the banner shows. A non-admin who reaches this page reads the values
/// and gets no fields and no Save.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.viewmodel});

  /// Injected by tests so the load and save paths run without a server.
  /// Production reads the app-scoped instance registered in `main.dart`, which
  /// is also what the till reads (Phase 4 F4).
  final StoreSettingsViewmodel? viewmodel;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _vatRateLabel = 'VAT rate (%)';
  static const _discountCapLabel = 'Discount cap (%)';

  late final StoreSettingsViewmodel _settings;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _vatRate = TextEditingController();
  final TextEditingController _discountCap = TextEditingController();
  bool _vatRegistered = StoreSettings.defaults.vatRegistered;

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
    super.dispose();
  }

  /// Copies the current values into the fields. Called on open and after the
  /// load answers, never while someone is typing.
  void _seedFields() {
    _vatRegistered = _settings.vatRegistered;
    _vatRate.text = _settings.vatRate.toStringAsFixed(2);
    _discountCap.text = _settings.discountCapPercent.toStringAsFixed(2);
  }

  Future<void> _load() async {
    await _settings.load();
    if (!mounted) return;
    setState(_seedFields);
  }

  double _percent(String raw) => double.parse(raw.trim());

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final saved = await _settings.save(
      vatRegistered: _vatRegistered,
      vatRate: _percent(_vatRate.text),
      discountCapPercent: _percent(_discountCap.text),
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
      selectedNavigationIndex: 6,
      child: LayoutBuilder(
        builder: (context, slot) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: slot.maxWidth < _readingWidth
                ? double.infinity
                : _readingWidth,
            child: ListenableBuilder(
              listenable: _settings,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppPanel(
                    title: 'Sales settings',
                    child: isAdmin ? _form(context) : _readOnly(context),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _StoreInformationCard(),
                ],
              ),
            ),
          ),
        ),
      ),
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
                  children: const [
                    Text('VAT registered', style: TextStyle(fontSize: 15)),
                    SizedBox(height: 2),
                    Text(
                      'Break out VAT on receipts and reports.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
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
        const SizedBox(height: AppSpacing.lg),
        const InfoBanner(message: 'Only an Admin can change these settings.'),
      ],
    );
  }
}

/// One percent input with the shared rule as its validator.
class _PercentField extends StatelessWidget {
  const _PercentField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (value) => StoreSettings.percentError(value ?? ''),
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
      title: 'Store information',
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
          const Text(
            'Editing store details is not available yet.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
