import 'package:client/core/constants/app_text_styles.dart';
import 'package:flutter/material.dart';

/// The heading above one dashboard list: its name, and the single quiet action
/// that opens the screen the list summarises.
///
/// `DataPanel` brings the card, the rows and the empty, loading and error states
/// but has no heading of its own, and wrapping it in an `AppPanel` would draw a
/// second border around the first. So the heading sits ABOVE the card, in the
/// same Cinzel as an `AppPanel` title, and the page still reads as titled panels.
class InventoryPanelHeader extends StatelessWidget {
  const InventoryPanelHeader({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;

  /// Worded by the caller. Every dashboard panel has exactly one, because a
  /// summary the user cannot open is a dead end.
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTextStyles.cinzelFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
