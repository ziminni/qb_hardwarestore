import 'package:flutter/material.dart';

/// Search + role/status controls for the staff account list.
///
/// Search runs server-side (`?search=`); role and status narrow the loaded
/// rows client-side. All no-op controls from the mock era are gone — every
/// control here calls its callback.
class AdminUserFilters extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            key: const Key('userSearchField'),
            controller: TextEditingController(text: initialQuery),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search name, username, or email',
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: onSearch,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: roleFilter,
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
              for (final role in availableRoles)
                DropdownMenuItem<String?>(value: role, child: Text(role)),
            ],
            onChanged: onRoleChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<bool?>(
            initialValue: activeFilter,
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
            onChanged: onActiveChanged,
          ),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: onClear, child: const Text('Clear')),
      ],
    );
  }
}
