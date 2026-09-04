import 'package:flutter/material.dart';

class AdminUserFilters extends StatelessWidget {
  const AdminUserFilters({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          flex: 2,
          child: TextField(
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search name, username, or email',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: () {},
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('Role: All roles'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: () {},
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('Status: All statuses'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: () {}, child: const Text('Clear')),
      ],
    );
  }
}
