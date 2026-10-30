import 'package:client/shared/widgets/activity_list_item.dart';
import 'package:flutter/material.dart';

class InventoryListItem extends StatelessWidget {
  const InventoryListItem({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return ActivityListItem(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
    );
  }
}
