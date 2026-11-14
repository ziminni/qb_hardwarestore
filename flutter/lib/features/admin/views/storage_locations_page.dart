import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/features/admin/viewmodels/storage_locations_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Where the shop keeps things: the Admin-managed list of pick-up points
/// (Phase 5 B4 wire, F4 screen; decision 18 "Bodega lite").
///
/// **A label, not a stock ledger.** Nothing here counts stock per location and
/// nothing transfers stock between them; deactivating one changes what the
/// product picker offers, and the products already assigned keep their label
/// because the goods did not move.
///
/// **Admin only, and the fence is the route's** (`/admin/…` in
/// `AppRoutes.redirectFor`): the server refuses every write for any other role
/// (`IsAdminRole`), so a typed address from another account lands on that
/// account's own dashboard instead of a screen whose every button would 403.
///
/// **No Delete.** The route answers 405 to DELETE, so deactivate is the exit and
/// restore is the same PATCH with the other flag.
class StorageLocationsPage extends StatelessWidget {
  const StorageLocationsPage({super.key, this.viewmodel});

  /// Injected by tests so a state can be rendered without a server.
  final StorageLocationsViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? StorageLocationsViewmodel())..load(),
    child: const _StorageLocationsBody(),
  );
}

class _StorageLocationsBody extends StatefulWidget {
  const _StorageLocationsBody();

  @override
  State<_StorageLocationsBody> createState() => _StorageLocationsBodyState();
}

class _StorageLocationsBodyState extends State<_StorageLocationsBody> {
  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _create() async {
    final state = context.read<StorageLocationsViewmodel>();
    state.clearActionError();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _LocationNameDialog(
        title: 'New storage location',
        actionLabel: 'Add location',
        subtitle: 'A place goods are kept: a room, a yard, a shelf area.',
        // The SERVER's comparison, checked before the round trip: two places
        // with one name would print the same pick-up point twice.
        validate: (value) => state.nameTaken(value) ? _duplicate(value) : null,
      ),
    );
    if (name == null || !mounted) return;
    final error = await state.create(name);
    if (!mounted) return;
    _say(error ?? '"$name" added.');
  }

  Future<void> _rename(StorageLocation location) async {
    final state = context.read<StorageLocationsViewmodel>();
    state.clearActionError();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _LocationNameDialog(
        title: 'Rename storage location',
        actionLabel: 'Save changes',
        subtitle: location.name,
        initial: location.name,
        helperText:
            'Products stored here keep this location under its new name.',
        validate: (value) => state.nameTaken(value, excludingId: location.id)
            ? _duplicate(value)
            : null,
      ),
    );
    if (name == null || !mounted) return;
    if (name.trim() == location.name) return;
    final error = await state.rename(location, name);
    if (!mounted) return;
    _say(error ?? 'Renamed to "${name.trim()}".');
  }

  Future<void> _toggle(StorageLocation location) async {
    final state = context.read<StorageLocationsViewmodel>();
    final deactivating = location.isActive;
    if (deactivating) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          icon: Icons.visibility_off_outlined,
          title: 'Deactivate ${location.name}?',
          width: 460,
          content: const Text(
            'It leaves the product form, so no product can be moved here. '
            'Products already stored here keep the label.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final error = await state.setActive(location, !deactivating);
    if (!mounted) return;
    _say(
      error ?? '${location.name} ${deactivating ? 'deactivated' : 'restored'}.',
    );
  }

  static String _duplicate(String name) =>
      '"${name.trim()}" is already a storage location. Two places with one '
      'name would show the same pick-up point twice.';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<StorageLocationsViewmodel>();
    final rows = state.rows;
    final refusal = state.actionError;
    // One failure, never a failure plus an empty state under it.
    final showBanner = state.loadError != null && !state.isLoading;

    final content = ListView(
      padding: EdgeInsets.zero,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              key: const ValueKey('storage-location-create'),
              onPressed: state.isCreating ? null : _create,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New location'),
            ),
            Text(
              'A room, a yard or a shelf area. Not a stock count.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // Numbers only once a load has answered: a failed read showing "0
        // locations" would be a claim nobody checked.
        if (state.loadError == null && !state.isLoading)
          MetricGrid(
            children: [
              MetricTile(
                label: 'Locations',
                value: formatCount(state.locations.length),
              ),
              MetricTile(
                label: 'Active',
                value: formatCount(state.activeCount),
              ),
              MetricTile(
                label: 'Deactivated',
                value: formatCount(state.inactiveCount),
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
        if (showBanner)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ErrorBanner(message: state.loadError!, onRetry: state.load),
          ),
        if (refusal != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ErrorBanner(
              message: refusal,
              onRetry: state.clearActionError,
            ),
          ),
        _table(state, rows),
      ],
    );

    return AdminSkeletonLayout(
      title: 'Storage locations',
      subtitle: 'Where the shop keeps things, and what the till prints.',
      // Appended after Deliveries (9), so no earlier index moved.
      selectedNavigationIndex: 10,
      scrollable: false,
      // The admin shell navigates from its own tuple list, so it needs no
      // callback here.
      child: content,
    );
  }

  Widget _table(StorageLocationsViewmodel state, List<StorageLocation> rows) {
    return DataPanel<StorageLocation>(
      title: 'Storage locations',
      count: rows.length,
      rows: rows,
      isLoading: state.isLoading && state.locations.isEmpty,
      error: state.locations.isEmpty ? state.loadError : null,
      onRetry: state.load,
      emptyMessage:
          'No storage locations yet. Add the places this shop keeps goods in.',
      rowKey: (location) => ValueKey('storage-location.${location.id}'),
      columns: [
        DataPanelColumn<StorageLocation>(
          label: 'Location',
          flex: 3,
          cell: (location) => Text(
            location.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataPanelColumn<StorageLocation>(
          label: 'Status',
          flex: 2,
          cell: (location) => StatusBadge(
            label: location.isActive ? 'Active' : 'Deactivated',
            tone: location.isActive ? StatusTone.success : StatusTone.neutral,
          ),
        ),
        DataPanelColumn<StorageLocation>(
          label: 'Shown',
          flex: 2,
          cell: (location) => Text(
            location.isActive
                ? 'On the till and the receipt'
                : 'On old products only',
            maxLines: 2,
          ),
        ),
        DataPanelColumn<StorageLocation>(
          label: 'Actions',
          flex: 3,
          cell: (location) => _actions(state, location),
        ),
      ],
    );
  }

  Widget _actions(StorageLocationsViewmodel state, StorageLocation location) {
    final busy = state.isBusy(location.id);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          key: ValueKey('storage-location-rename-${location.id}'),
          onPressed: busy ? null : () => _rename(location),
          child: const Text('Rename'),
        ),
        // Deactivate, never Delete: the route answers 405, because a location a
        // product still points at must not vanish from under the label.
        TextButton(
          key: ValueKey('storage-location-toggle-${location.id}'),
          onPressed: busy ? null : () => _toggle(location),
          child: Text(location.isActive ? 'Deactivate' : 'Restore'),
        ),
      ],
    );
  }
}

/// The one name dialog: create and rename differ only in their words.
///
/// A refused name keeps the dialog open on the sentence, because closing it would
/// leave the clerk with a message and no way to correct the row.
class _LocationNameDialog extends StatefulWidget {
  const _LocationNameDialog({
    required this.title,
    required this.actionLabel,
    required this.validate,
    this.subtitle,
    this.initial = '',
    this.helperText = 'This is what the till and the receipt print.',
  });

  final String title;
  final String actionLabel;
  final String? subtitle;
  final String initial;
  final String helperText;
  final String? Function(String) validate;

  @override
  State<_LocationNameDialog> createState() => _LocationNameDialogState();
}

class _LocationNameDialogState extends State<_LocationNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.warehouse_outlined,
      title: widget.title,
      subtitle: widget.subtitle,
      width: 520,
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('storage-location-name'),
          controller: _name,
          autofocus: true,
          textInputAction: TextInputAction.done,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: 'Location name',
            hintText: 'Bodega',
            helperText: widget.helperText,
          ),
          validator: (value) {
            final raw = (value ?? '').trim();
            if (raw.isEmpty) return 'Enter a name for the location.';
            return widget.validate(raw);
          },
          // Enter submits, so the field needs no mouse (and the dialog's Esc
          // still closes it from anywhere inside).
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('storage-location-submit'),
          onPressed: _submit,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
