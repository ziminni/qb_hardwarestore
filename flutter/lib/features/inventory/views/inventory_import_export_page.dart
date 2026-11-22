import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/features/catalogue_io/import_export_actions.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Every import and export the stocker has, on one page (owner 2026-11-18).
///
/// The same dialogs the Products page buttons open (`import_export_actions`),
/// gathered here so nobody has to know they live under Products. Nothing here
/// changes stock: the Excel round-trip is catalogue only (decision 23).
class InventoryImportExportPage extends StatefulWidget {
  const InventoryImportExportPage({super.key});

  /// Appended to the Stock menu, so no earlier index moved.
  static int get navigationIndex =>
      AppDestinations.indexOf('inventory.import-export', AppAreas.inventory);

  @override
  State<InventoryImportExportPage> createState() =>
      _InventoryImportExportPageState();
}

class _InventoryImportExportPageState extends State<InventoryImportExportPage> {
  @override
  void initState() {
    super.initState();
    // The dialogs read the catalogue the store already holds; load it once if
    // this page is the first one opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inventory = context.read<InventoryViewmodel>();
      if (!inventory.hasLoaded && !inventory.isLoading) inventory.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final ready = inventory.hasLoaded && !inventory.isLoading;
    return InventorySkeletonLayout(
      title: 'Import & export',
      subtitle: 'Excel files, barcode lists and labels, in one place.',
      selectedNavigationIndex: InventoryImportExportPage.navigationIndex,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inventory.loadError != null) ...[
            ErrorBanner(message: inventory.loadError!, onRetry: inventory.load),
            const SizedBox(height: AppSpacing.md),
          ],
          if (!ready && inventory.loadError == null) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
          ],
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: [
              _ActionCard(
                key: const ValueKey('io-export-excel'),
                icon: Icons.table_view_outlined,
                title: 'Export catalogue to Excel',
                body:
                    'Every product and variant with its unit, price, category '
                    'and where it is kept. Stock quantities are not in the file.',
                action: 'Export',
                onPressed: ready ? () => openCatalogueExport(context) : null,
              ),
              _ActionCard(
                key: const ValueKey('io-export-stock-records'),
                icon: Icons.inventory_outlined,
                title: 'Export stock records to Excel',
                body:
                    'Live on-hand quantities, low-stock thresholds, unit cost, '
                    'stock value, selling price, SKU and barcode per variant.',
                action: 'Export stock',
                onPressed: ready
                    ? () => exportStockRecordsToExcel(context)
                    : null,
              ),
              _ActionCard(
                key: const ValueKey('io-template'),
                icon: Icons.note_add_outlined,
                title: 'Download import template',
                body:
                    'An empty catalogue file for adding products in bulk, with '
                    'example rows, your categories, brands and units, and a '
                    '"How to fill" sheet. Fill it in, then import it.',
                action: 'Download template',
                onPressed: ready ? () => downloadImportTemplate(context) : null,
              ),
              _ActionCard(
                key: const ValueKey('io-import-excel'),
                icon: Icons.upload_file_outlined,
                title: 'Import catalogue from Excel',
                body:
                    'Bring back an edited export. You see every change before '
                    'anything is saved. An import never changes stock.',
                action: 'Import',
                onPressed: ready ? () => openCatalogueImport(context) : null,
              ),
              _ActionCard(
                key: const ValueKey('io-barcode-list'),
                icon: Icons.qr_code_2_rounded,
                title: 'Barcode list',
                body:
                    'Every barcode in the catalogue, to print or to download '
                    'as PDF or CSV.',
                action: 'Open',
                onPressed: ready ? () => openBarcodeList(context) : null,
              ),
              _ActionCard(
                key: const ValueKey('io-labels'),
                icon: Icons.label_outline_rounded,
                title: 'Print product labels',
                body:
                    'Labels are printed for the products you pick: tick them '
                    'on the Products page, then press Print labels. New '
                    'deliveries also offer labels in Receiving.',
                action: 'Go to Products',
                onPressed: () => context.go(AppRoutes.inventoryProducts),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: AppColors.brandGoldText),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onPressed, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }
}
