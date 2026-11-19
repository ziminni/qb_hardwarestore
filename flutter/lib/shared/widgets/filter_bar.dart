import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// Search field plus filter chips, the head of every list screen.
///
/// The chips live in a `Wrap`, so a 360 px window folds them onto more lines
/// instead of overflowing the way the per-page `Row`s did.
class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    this.searchController,
    this.searchHint = 'Search',
    this.onSearchChanged,
    this.options = const <String>[],
    this.optionsLabel,
    this.selected,
    this.onSelected,
    this.extraOptions = const <String>[],
    this.extraOptionsLabel,
    this.extraSelected,
    this.onExtraSelected,
  });

  /// Owned by the page when it needs to clear or prefill the field; the bar
  /// makes its own when this is null.
  final TextEditingController? searchController;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;

  /// Chip labels, in display order. Include the "All" chip here if the page
  /// wants one.
  final List<String> options;

  /// Optional micro-label displayed beside or above [options] (e.g. "Role").
  final String? optionsLabel;

  /// The active chip, or null when nothing is filtered.
  final String? selected;

  /// Tapping a chip reports its label. The page owns the selection and echoes
  /// it back through [selected], so a filter can be driven from the data layer.
  /// A page that needs a way out of the filter gives the bar an "All" chip.
  final ValueChanged<String>? onSelected;

  /// A second, independent chip group under the first, for a page whose two
  /// filters combine (a status AND a date range). It keeps its own selection, so
  /// neither group can silently clear the other.
  final List<String> extraOptions;

  /// Optional micro-label displayed beside or above [extraOptions] (e.g. "Status").
  final String? extraOptionsLabel;

  /// The active chip in [extraOptions], if any.
  final String? extraSelected;

  /// Reports a tap in [extraOptions].
  final ValueChanged<String>? onExtraSelected;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late TextEditingController _controller;

  /// Whether the current controller is this bar's to dispose.
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _bind(widget.searchController);
  }

  @override
  void didUpdateWidget(FilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchController == oldWidget.searchController) return;
    // The page changed its mind about the controller: drop the one we made (if
    // it was ours) and follow the new one. The page's controller is never
    // disposed here, it outlives this bar.
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _bind(widget.searchController);
  }

  void _bind(TextEditingController? parentController) {
    _ownsController = parentController == null;
    _controller = parentController ?? TextEditingController();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _clearSearch() {
    _controller.clear();
    widget.onSearchChanged?.call('');
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // Only the controller this bar created is ours to dispose.
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final hasQuery = _controller.text.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: widget.onSearchChanged,
          style: TextStyle(fontSize: 14, color: p.textPrimary),
          decoration: InputDecoration(
            hintText: widget.searchHint,
            hintStyle: TextStyle(fontSize: 14, color: p.textSecondary),
            filled: true,
            fillColor: p.surfaceSunken,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 19,
              color: hasQuery ? p.accentInk : p.textSecondary,
            ),
            suffixIcon: hasQuery
                ? IconButton(
                    tooltip: 'Clear search',
                    onPressed: _clearSearch,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: p.textSecondary,
                    ),
                  )
                : null,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.medium),
              borderSide: BorderSide(color: p.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.medium),
              borderSide: BorderSide(color: p.accent, width: 1.5),
            ),
          ),
        ),
        if (widget.options.isNotEmpty) ...[
          const SizedBox(height: 12),
          _chipGroup(
            context,
            label: widget.optionsLabel,
            options: widget.options,
            selected: widget.selected,
            onSelected: widget.onSelected,
          ),
        ],
        if (widget.extraOptions.isNotEmpty) ...[
          const SizedBox(height: 8),
          _chipGroup(
            context,
            label: widget.extraOptionsLabel,
            options: widget.extraOptions,
            selected: widget.extraSelected,
            onSelected: widget.onExtraSelected,
          ),
        ],
      ],
    );
  }

  Widget _chipGroup(
    BuildContext context, {
    required String? label,
    required List<String> options,
    required String? selected,
    required ValueChanged<String>? onSelected,
  }) {
    final p = AppPalette.of(context);
    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (label != null && label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: p.textSecondary,
              ),
            ),
          ),
        for (final option in options)
          _FilterChipButton(
            label: option,
            selected: option == selected,
            onTap: () => onSelected?.call(option),
          ),
      ],
    );
    return chips;
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: selected ? p.selected : p.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: selected ? p.accent : p.border,
          width: selected ? 1.25 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          hoverColor: p.selected.withValues(alpha: 0.45),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: p.accentInk,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? p.accentInk : p.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
