import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

/// Renders the loading, error, empty and data states of a data-backed screen in
/// one place.
///
/// Decision 07: 27 screens are synchronous today and have none of these states,
/// and handling them per-screen is the dynamic that produced that inconsistency.
/// This widget owns the rendering; the only thing a screen varies is its own
/// empty-state copy, so a list that is empty because of a filter reads
/// differently from one that is empty because nothing exists yet.
///
/// **Precedence is part of the contract: loading, then error, then empty, then
/// data.** The two orderings that matter, and why:
///
/// - *Loading outranks error.* A retry holds the previous error while the next
///   attempt is in flight; showing it would flash a stale failure.
/// - *Error outranks empty.* `isEmpty` is usually true after a failed first
///   load, and reporting "no products match these filters" when the request
///   actually failed is a lie the user cannot see through.
///
/// [builder] runs **only** for the data state, so a screen cannot dereference
/// absent data while a fetch is in flight.
///
/// The viewmodel feeding this follows the `auth_viewmodel` public-field
/// convention (`bool isLoading`, `String? error`, a data list) — see
/// `features/auth/viewmodels/auth_viewmodel.dart` for the one working example.
class AsyncView extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.isLoading,
    required this.error,
    required this.isEmpty,
    required this.emptyMessage,
    required this.onRetry,
    required this.builder,
  });

  /// A fetch is in flight. Outranks every other state.
  final bool isLoading;

  /// The failure to show, or null. Outranks [isEmpty].
  final String? error;

  /// The fetch succeeded and returned nothing.
  final bool isEmpty;

  /// Screen-specific copy for the empty state.
  final String emptyMessage;

  /// Called by the error state's Retry button.
  final VoidCallback onRetry;

  /// Builds the data state. Never called while loading, in error, or empty.
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final failure = error;
    if (failure != null) {
      return _ErrorState(message: failure, onRetry: onRetry);
    }

    if (isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return builder(context);
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: colors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
