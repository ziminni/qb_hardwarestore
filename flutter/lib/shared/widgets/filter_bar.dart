import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
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
    this.selected,
    this.onSelected,
    this.extraOptions = const <String>[],
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
    if (_ownsController) _controller.dispose();
    _bind(widget.searchController);
  }

  void _bind(TextEditingController? parentController) {
    _ownsController = parentController == null;
    _controller = parentController ?? TextEditingController();
  }

  @override
  void dispose() {
    // Only the controller this bar created is ours to dispose.
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: widget.onSearchChanged,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.searchHint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            prefixIcon: const Icon(Icons.search, size: 18),
          ),
        ),
        if (widget.options.isNotEmpty) ...[
          const SizedBox(height: 12),
          _chipRow(widget.options, widget.selected, widget.onSelected),
        ],
        if (widget.extraOptions.isNotEmpty) ...[
          const SizedBox(height: 8),
          _chipRow(
            widget.extraOptions,
            widget.extraSelected,
            widget.onExtraSelected,
          ),
        ],
      ],
    );
  }

  Widget _chipRow(
    List<String> options,
    String? selected,
    ValueChanged<String>? onSelected,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _FilterChipButton(
            label: option,
            selected: option == selected,
            onTap: () => onSelected?.call(option),
          ),
      ],
    );
  }
}

/// Gold dark enough to read on a light tint.
const Color _goldInk = Color(0xFF6E5A22);

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
    return Container(
      decoration: BoxDecoration(
        color: selected ? AppColors.selected : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: selected ? AppColors.brandGold : AppColors.border,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? _goldInk : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
