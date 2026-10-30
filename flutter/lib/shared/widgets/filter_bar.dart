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

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final TextEditingController _controller =
      widget.searchController ?? TextEditingController();

  @override
  void dispose() {
    // Only the controller this bar created is ours to dispose.
    if (widget.searchController == null) {
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in widget.options)
                _FilterChipButton(
                  label: option,
                  selected: option == widget.selected,
                  onTap: () => widget.onSelected?.call(option),
                ),
            ],
          ),
        ],
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
