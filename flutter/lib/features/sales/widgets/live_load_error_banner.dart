import 'package:client/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

/// Error banner for the live sales screens.
///
/// A failed load keeps the old rows (the viewmodels never clear on error),
/// so without this the screen would silently show stale data — or an empty
/// table that reads as "no sales". The banner makes the failure visible and
/// gives the user a retry path.
class LiveLoadErrorBanner extends StatelessWidget {
  const LiveLoadErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
