import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

/// One error-with-retry style for the whole app.
///
/// A failed load keeps the last good rows on screen, so without a banner the
/// page silently shows stale data. The banner names the failure and gives the
/// user the retry path. [onRetry] is optional because some failures are not
/// retryable (a permission problem); no button beats a dead button.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorTint,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: AppColors.errorText),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.errorText, fontSize: 14),
            ),
          ),
          ?onRetry == null
              ? null
              : TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.errorText,
                  ),
                  child: const Text('Retry'),
                ),
        ],
      ),
    );
  }
}
