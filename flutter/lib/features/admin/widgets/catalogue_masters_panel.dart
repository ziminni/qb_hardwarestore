import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/repositories/catalogue_repository.dart';
import 'package:client/data/services/catalogue_service.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

enum CatalogueMasterKind { brands, units }

/// Viewmodel for Admin Settings -> Brands and Units (UOM), reading and writing
/// the live `/api/v1/brands/` and `/api/v1/uoms/` endpoints.
class CatalogueMastersViewmodel extends ChangeNotifier {
  CatalogueMastersViewmodel({CatalogueRepository? repository})
    : _repository = repository ?? CatalogueRepository();

  final CatalogueRepository _repository;

  List<Brand> _brands = const [];
  List<UnitOfMeasure> _units = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadError;

  List<Brand> get brands => List.unmodifiable(_brands);
  List<UnitOfMeasure> get units => List.unmodifiable(_units);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get loadError => _loadError;

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.fetchBrands(),
        _repository.fetchUnits(),
      ]);
      _brands = [...(results[0] as List<Brand>)]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _units = [...(results[1] as List<UnitOfMeasure>)]
        ..sort((a, b) => a.code.toLowerCase().compareTo(b.code.toLowerCase()));
    } on CatalogueServiceException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> _write(Future<void> Function() action) async {
    if (_isSaving) return 'Still saving the previous change.';
    _isSaving = true;
    notifyListeners();
    try {
      await action();
    } on CatalogueServiceException catch (error) {
      return error.message;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
    await load();
    return null;
  }

  Future<String?> saveBrand({int? id, required String name}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value('Brand name is required.');
    return _write(
      () async => id == null
          ? await _repository.createBrand(trimmed)
          : await _repository.patchBrand(id, name: trimmed),
    );
  }

  Future<String?> saveUnit({
    int? id,
    required String code,
    required String name,
  }) {
    final cleanCode = code.trim().toUpperCase();
    final cleanName = name.trim();
    if (cleanCode.isEmpty || cleanName.isEmpty) {
      return Future.value('Both unit code and name are required.');
    }
    return _write(
      () async => id == null
          ? await _repository.createUnit(code: cleanCode, name: cleanName)
          : await _repository.patchUnit(id, code: cleanCode, name: cleanName),
    );
  }
}

/// Admin Settings panel for managing **Brands** or **Units (UOM)** against the
/// live catalogue endpoints.
class CatalogueMastersPanel extends StatefulWidget {
  const CatalogueMastersPanel({
    super.key,
    required this.kind,
    required this.canEdit,
    this.viewmodel,
  });

  final CatalogueMasterKind kind;
  final bool canEdit;
  final CatalogueMastersViewmodel? viewmodel;

  @override
  State<CatalogueMastersPanel> createState() => _CatalogueMastersPanelState();
}

class _CatalogueMastersPanelState extends State<CatalogueMastersPanel> {
  late final CatalogueMastersViewmodel _vm;
  late final bool _ownsVm;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ownsVm = widget.viewmodel == null;
    _vm = widget.viewmodel ?? CatalogueMastersViewmodel();
    _vm.load();
  }

  @override
  void dispose() {
    _search.dispose();
    if (_ownsVm) _vm.dispose();
    super.dispose();
  }

  Future<void> _openBrandDialog({Brand? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _BrandFormDialog(viewmodel: _vm, existing: existing),
    );
  }

  Future<void> _openUnitDialog({UnitOfMeasure? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _UnitFormDialog(viewmodel: _vm, existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final isBrands = widget.kind == CatalogueMasterKind.brands;
    final ctaBg = p.isDark ? p.accent : AppColors.brandBlack;
    final ctaFg = p.isDark ? p.onAccent : AppColors.brandWhite;

    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final q = _query.trim().toLowerCase();
        final brands = [
          for (final b in _vm.brands)
            if (q.isEmpty || b.name.toLowerCase().contains(q)) b,
        ];
        final units = [
          for (final u in _vm.units)
            if (q.isEmpty ||
                '${u.code} ${u.name}'.toLowerCase().contains(q))
              u,
        ];
        final totalCount = isBrands ? _vm.brands.length : _vm.units.length;
        final shownCount = isBrands ? brands.length : units.length;

        return AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isBrands ? 'Store brands' : 'Units of measure',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(
                        label: '$shownCount of $totalCount',
                        tone: StatusTone.info,
                      ),
                    ],
                  ),
                  if (widget.canEdit)
                    FilledButton.icon(
                      key: ValueKey(isBrands ? 'add-brand' : 'add-unit'),
                      onPressed: _vm.isSaving
                          ? null
                          : () => isBrands
                              ? _openBrandDialog()
                              : _openUnitDialog(),
                      style: FilledButton.styleFrom(
                        backgroundColor: ctaBg,
                        foregroundColor: ctaFg,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.medium),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: Text(isBrands ? 'Add brand' : 'Add unit'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              FilterBar(
                searchController: _search,
                searchHint: isBrands
                    ? 'Search brands'
                    : 'Search unit code or name',
                onSearchChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_vm.loadError != null) ...[
                ErrorBanner(message: _vm.loadError!, onRetry: _vm.load),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_vm.isLoading && totalCount == 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (shownCount == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    q.isNotEmpty
                        ? 'No ${isBrands ? 'brands' : 'units'} match "$q".'
                        : 'No ${isBrands ? 'brands' : 'units'} recorded yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: p.textSecondary),
                  ),
                )
              else if (isBrands)
                for (var i = 0; i < brands.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: p.surfaceSunken,
                            borderRadius: BorderRadius.circular(AppRadii.small),
                            border: Border.all(color: p.border),
                          ),
                          child: Icon(
                            Icons.sell_outlined,
                            size: 16,
                            color: p.accentInk,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            brands[i].name,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (widget.canEdit)
                          TextButton.icon(
                            onPressed: () =>
                                _openBrandDialog(existing: brands[i]),
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Text('Rename'),
                          ),
                      ],
                    ),
                  ),
                ]
              else
                for (var i = 0; i < units.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          constraints: const BoxConstraints(minWidth: 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.selected,
                            borderRadius: BorderRadius.circular(AppRadii.small),
                            border: Border.all(
                              color: p.accent.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            units[i].code,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: p.accentInk,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                units[i].name,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: p.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              StatusBadge(
                                label: units[i].isWhole
                                    ? 'Whole unit'
                                    : 'Fractional allowed',
                                tone: units[i].isWhole
                                    ? StatusTone.neutral
                                    : StatusTone.success,
                              ),
                            ],
                          ),
                        ),
                        if (widget.canEdit)
                          TextButton.icon(
                            onPressed: () =>
                                _openUnitDialog(existing: units[i]),
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Text('Edit'),
                          ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _BrandFormDialog extends StatefulWidget {
  const _BrandFormDialog({required this.viewmodel, this.existing});

  final CatalogueMastersViewmodel viewmodel;
  final Brand? existing;

  @override
  State<_BrandFormDialog> createState() => _BrandFormDialogState();
}

class _BrandFormDialogState extends State<_BrandFormDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final msg = await widget.viewmodel.saveBrand(
      id: widget.existing?.id,
      name: _controller.text,
    );
    if (!mounted) return;
    if (msg == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AppDialog(
      icon: Icons.sell_outlined,
      title: isNew ? 'Add brand' : 'Rename brand',
      subtitle: 'Brands appear in every product picker across the store.',
      width: 440,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: AppColors.errorText),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Brand name',
              hintText: 'e.g. Holcim, Davies, FlowPro',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(isNew ? 'Add brand' : 'Save'),
        ),
      ],
    );
  }
}

class _UnitFormDialog extends StatefulWidget {
  const _UnitFormDialog({required this.viewmodel, this.existing});

  final CatalogueMastersViewmodel viewmodel;
  final UnitOfMeasure? existing;

  @override
  State<_UnitFormDialog> createState() => _UnitFormDialogState();
}

class _UnitFormDialogState extends State<_UnitFormDialog> {
  late final TextEditingController _codeController = TextEditingController(
    text: widget.existing?.code ?? '',
  );
  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final msg = await widget.viewmodel.saveUnit(
      id: widget.existing?.id,
      code: _codeController.text,
      name: _nameController.text,
    );
    if (!mounted) return;
    if (msg == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AppDialog(
      icon: Icons.straighten_rounded,
      title: isNew ? 'Add unit of measure' : 'Edit unit',
      subtitle:
          'Whole-unit rules are enforced by the server to keep stock '
          'counts consistent.',
      width: 460,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: AppColors.errorText),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            controller: _codeController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Unit code',
              hintText: 'e.g. PC, BAG, SHEET, KG, M',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Unit name',
              hintText: 'e.g. Piece, Bag, Sheet, Kilogram, Meter',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(isNew ? 'Add unit' : 'Save'),
        ),
      ],
    );
  }
}
