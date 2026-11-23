import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/reports_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The Reports area's front door: every report as a card, grouped by section.
///
/// This replaces "one screen with four tabs" as the way a reader finds a report
/// (planning/reports-suite/MAP.md: catalogue home + one shared viewer). The old
/// tabbed body is still reachable at `/sales/reports`; this is the new path.
class ReportsCataloguePage extends StatelessWidget {
  const ReportsCataloguePage({super.key, this.shell = ReportsShell.sales});

  final ReportsShell shell;

  @override
  Widget build(BuildContext context) {
    return ReportsShellScaffold(
      shell: shell,
      child: ReportsCatalogueView(shell: shell),
    );
  }
}

/// The catalogue body, without a shell, so it renders in any of the Reports
/// shells and in a test.
class ReportsCatalogueView extends StatelessWidget {
  const ReportsCatalogueView({
    super.key,
    this.shell = ReportsShell.sales,
    this.areas,
    this.onOpen,
  });

  final ReportsShell shell;

  /// The areas the signed-in account holds. Defaults to the shell's own area,
  /// which is what the router guarantees: a stocker only ever reaches the
  /// inventory shell, a manager only the sales one.
  final Set<String>? areas;

  /// What a live card does with its report id. Production leaves it null and
  /// routes to the shared viewer; tests pass a recorder.
  final ValueChanged<String>? onOpen;

  void _open(BuildContext context, ReportDefinition report) {
    final open = onOpen;
    if (open != null) {
      open(report.id);
      return;
    }
    context.go(shell.viewerPath(report.id));
  }

  @override
  Widget build(BuildContext context) {
    final visible = reportSectionsFor(areas ?? {shell.area});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in ReportSection.values)
          if (visible.contains(section)) _Section(section: section, onOpen: _open),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section, required this.onOpen});

  final ReportSection section;
  final void Function(BuildContext context, ReportDefinition report) onOpen;

  @override
  Widget build(BuildContext context) {
    final reports = reportCatalogue
        .where((report) => report.section == section)
        .toList();
    if (reports.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            section.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final report in reports)
                _ReportCard(
                  report: report,
                  onTap: report.available
                      ? () => onOpen(context, report)
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One report card. A card with no endpoint behind it keeps its shape but takes
/// no tap and carries the "P1" tag, so a reader sees what is coming without
/// pressing a door that opens onto nothing.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, this.onTap});

  final ReportDefinition report;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return SizedBox(
      width: 300,
      child: Material(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: InkWell(
          key: ValueKey('report-card-${report.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.large),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.large),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        report.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (!report.available) const _P1Tag(),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  report.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _P1Tag extends StatelessWidget {
  const _P1Tag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'P1',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
