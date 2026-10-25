import 'package:flutter/material.dart';

/// Search + role/status controls for the staff account list.
///
/// Search runs server-side (`?search=`); role and status narrow the loaded
/// rows client-side. All no-op controls from the mock era are gone — every
/// control here calls its callback.
class AdminUserFilters extends StatefulWidget {
  const AdminUserFilters({
    super.key,
    required this.initialQuery,
    required this.availableRoles,
    required this.roleFilter,
    required this.activeFilter,
    required this.onSearch,
    required this.onRoleChanged,
    required this.onActiveChanged,
    required this.onClear,
  });

  final String initialQuery;
  final List<String> availableRoles;
  final String? roleFilter;
  final bool? activeFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onRoleChanged;
  final ValueChanged<bool?> onActiveChanged;
  final VoidCallback onClear;

  @override
  State<AdminUserFilters> createState() => _AdminUserFiltersState();
}

class _AdminUserFiltersState extends State<AdminUserFilters> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Owned once, not rebuilt: a controller built in `build` reverts the
    // field to the last submitted query on every unrelated rebuild (e.g.
    // setting a role filter discards what was just typed).
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(AdminUserFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The query only changes from outside when it is submitted or cleared.
    if (oldWidget.initialQuery != widget.initialQuery &&
        _controller.text != widget.initialQuery) {
      _controller.text = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            key: const Key('userSearchField'),
            controller: _controller,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search name, username, or email',
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: widget.onSearch,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: widget.roleFilter,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Role',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All roles'),
              ),
              for (final role in widget.availableRoles)
                DropdownMenuItem<String?>(
                  value: role,
                  child: Text(role, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: widget.onRoleChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<bool?>(
            isExpanded: true,
            initialValue: widget.activeFilter,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Status',
            ),
            items: const [
              DropdownMenuItem<bool?>(value: null, child: Text('All statuses')),
              DropdownMenuItem<bool?>(value: true, child: Text('Active')),
              DropdownMenuItem<bool?>(value: false, child: Text('Inactive')),
            ],
            onChanged: widget.onActiveChanged,
          ),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: widget.onClear, child: const Text('Clear')),
      ],
    );
  }
}
