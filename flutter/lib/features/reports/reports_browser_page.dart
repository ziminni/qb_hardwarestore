import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/report_viewer_page.dart';
import 'package:client/features/reports/reports_shell.dart';
import 'package:client/shared/widgets/stitch_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Reports area's front door: an inner sidebar of reports on the left,
/// the selected report's content on the right.
///
/// This replaces the catalogue card grid (planning/reports-suite/MAP.md: the
/// Stitch-approved shells show grouped navigation, not buttons). The old card
/// grid stays in `reports_catalogue_page.dart` for reference; the router sends
/// readers here. Each sidebar group collapses; the Stock Manager sees the
/// INVENTORY group alone, with no sales figures anywhere on screen.
class ReportsBrowserPage extends StatelessWidget {
  const ReportsBrowserPage({super.key, this.shell = ReportsShell.sales});

  final ReportsShell shell;

  @override
  Widget build(BuildContext context) {
    return ReportsShellScaffold(
      shell: shell,
      child: ReportsBrowserView(shell: shell),
    );
  }
}

/// The browser body, without a shell, so it renders in any Reports shell and
/// in a test.
class ReportsBrowserView extends StatefulWidget {
  const ReportsBrowserView({
    super.key,
    this.shell = ReportsShell.sales,
    this.areas,
    this.repository,
    this.initialReportId,
  });

  final ReportsShell shell;

  /// The areas the signed-in account holds. Defaults to the shell's own area.
  final Set<String>? areas;

  /// Injected by tests so the viewer renders without a server.
  final ReportsRepository? repository;

  /// Opens on this report instead of the first one (deep links keep working).
  final String? initialReportId;

  @override
  State<ReportsBrowserView> createState() => _ReportsBrowserViewState();
}

class _ReportsBrowserViewState extends State<ReportsBrowserView> {
  /// The report showing on the right. Null only when nothing is available.
  late String? _selectedId = _firstAvailable()?.id;

  /// Collapsed groups, by section. Everything starts expanded.
  final Set<ReportSection> _collapsed = {};

  List<ReportDefinition> _available() {
    final held = widget.areas ?? _signedInAreas() ?? {widget.shell.area};
    final visible = reportSectionsFor(held);
    return [
      for (final section in ReportSection.values)
        if (visible.contains(section))
          for (final report in reportCatalogue)
            if (report.section == section &&
                report.available &&
                report.readableBy(held))
              report,
    ];
  }

  /// The signed-in account's areas, or null where no session is provided.
  Set<String>? _signedInAreas() {
    try {
      final codes = context.read<AuthViewmodel>().user?.areaCodes;
      return codes == null || codes.isEmpty ? null : codes.toSet();
    } on ProviderNotFoundException {
      return null;
    }
  }

  ReportDefinition? _firstAvailable() {
    final available = _available();
    if (available.isEmpty) return null;
    final initial = widget.initialReportId;
    if (initial != null) {
      for (final report in available) {
        if (report.id == initial) return report;
      }
    }
    return available.first;
  }

  @override
  Widget build(BuildContext context) {
    final available = _available();
    final selected = available.where((r) => r.id == _selectedId).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A narrow till window stacks the picker above the report instead of
        // squeezing a sidebar beside it.
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReportPicker(
                available: available,
                selectedId: selected?.id,
                onPick: (id) => setState(() => _selectedId = id),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: SingleChildScrollView(child: _content(selected))),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 268,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: StitchColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: StitchColors.cardBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A0F172A),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: _Sidebar(
                  shell: widget.shell,
                  areas: widget.areas,
                  selectedId: selected?.id,
                  collapsed: _collapsed,
                  onToggle: (section) => setState(() {
                    if (!_collapsed.remove(section)) _collapsed.add(section);
                  }),
                  onPick: (id) => setState(() => _selectedId = id),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: _content(selected)),
          ],
        );
      },
    );
  }

  Widget _content(ReportDefinition? selected) {
    if (selected == null) {
      return const Center(
        child: Text(
          'No reports available for this account.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ReportViewerView(
      key: ValueKey('report-browser-${selected.id}'),
      report: selected,
      repository: widget.repository,
    );
  }
}

/// The inner sidebar: collapsible SALES / INVENTORY groups of report rows.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.shell,
    this.areas,
    this.selectedId,
    required this.collapsed,
    required this.onToggle,
    required this.onPick,
  });

  final ReportsShell shell;
  final Set<String>? areas;
  final String? selectedId;
  final Set<ReportSection> collapsed;
  final ValueChanged<ReportSection> onToggle;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final visible = reportSectionsFor(areas ?? {shell.area});
    return ListView(
      shrinkWrap: true,
      children: [
        for (final section in ReportSection.values)
          if (visible.contains(section))
            _Group(
              section: section,
              collapsed: collapsed.contains(section),
              selectedId: selectedId,
              onToggle: () => onToggle(section),
              onPick: onPick,
            ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.section,
    required this.collapsed,
    this.selectedId,
    required this.onToggle,
    required this.onPick,
  });

  final ReportSection section;
  final bool collapsed;
  final String? selectedId;
  final VoidCallback onToggle;
  final ValueChanged<String> onPick;

  IconData _sectionIcon(ReportSection section) => switch (section) {
    ReportSection.sales => Icons.point_of_sale_outlined,
    ReportSection.inventory => Icons.inventory_2_outlined,
    ReportSection.kpis => Icons.insights_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final reports = reportCatalogue
        .where((report) => report.section == section && report.available)
        .toList();
    if (reports.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('report-group-${section.name}'),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _sectionIcon(section),
                  size: 15,
                  color: StitchColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      color: StitchColors.inkMuted,
                    ),
                  ),
                ),
                Icon(
                  collapsed ? Icons.expand_more : Icons.expand_less,
                  size: 18,
                  color: StitchColors.inkMuted,
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          for (final report in reports)
            _Row(
              report: report,
              selected: report.id == selectedId,
              onTap: () => onPick(report.id),
            ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.report,
    required this.selected,
    required this.onTap,
  });

  final ReportDefinition report;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected ? StitchColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: InkWell(
          key: ValueKey('report-row-${report.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    border: Border.all(
                      color: StitchColors.primary.withValues(alpha: 0.22),
                    ),
                  )
                : null,
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  margin: const EdgeInsets.only(right: 9),
                  decoration: BoxDecoration(
                    color: selected
                        ? StitchColors.primaryDeep
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Expanded(
                  child: Text(
                    report.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? StitchColors.primaryDeep
                          : StitchColors.ink,
                    ),
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

/// The narrow-window picker: the same reports as a dropdown, no sidebar.
class _ReportPicker extends StatelessWidget {
  const _ReportPicker({
    required this.available,
    this.selectedId,
    required this.onPick,
  });

  final List<ReportDefinition> available;
  final String? selectedId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const ValueKey('report-picker'),
      initialValue: selectedId,
      decoration: const InputDecoration(labelText: 'Report'),
      items: [
        for (final report in available)
          DropdownMenuItem(value: report.id, child: Text(report.title)),
      ],
      onChanged: (id) {
        if (id != null) onPick(id);
      },
    );
  }
}
