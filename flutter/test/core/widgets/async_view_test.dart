// One shared widget owns loading / error / empty rendering for every data
// screen (decision 07): 27 screens are synchronous today and have none of these
// states, and handling them per-screen is the dynamic that produced the current
// inconsistency.
//
// The precedence is part of the contract and is tested below: loading, then
// error, then empty, then data. The builder must NOT run for the first three —
// a screen that reaches into its data while a fetch is in flight is exactly the
// null-dereference this widget exists to prevent.

import 'package:client/core/widgets/async_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('AsyncView', () {
    testWidgets('shows a progress indicator while loading', (tester) async {
      var builderRan = false;

      await tester.pumpWidget(
        _host(
          AsyncView(
            isLoading: true,
            error: null,
            isEmpty: false,
            emptyMessage: 'Nothing here.',
            onRetry: () {},
            builder: (_) {
              builderRan = true;
              return const Text('DATA');
            },
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('DATA'), findsNothing);
      expect(builderRan, isFalse, reason: 'builder must not run while loading');
    });

    testWidgets('shows the error and a retry that calls onRetry', (tester) async {
      var retries = 0;
      var builderRan = false;

      await tester.pumpWidget(
        _host(
          AsyncView(
            isLoading: false,
            error: 'Could not reach the server.',
            isEmpty: false,
            emptyMessage: 'Nothing here.',
            onRetry: () => retries++,
            builder: (_) {
              builderRan = true;
              return const Text('DATA');
            },
          ),
        ),
      );

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(builderRan, isFalse, reason: 'builder must not run on error');

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('shows the empty message when there is no data', (tester) async {
      var builderRan = false;

      await tester.pumpWidget(
        _host(
          AsyncView(
            isLoading: false,
            error: null,
            isEmpty: true,
            emptyMessage: 'No products match these filters.',
            onRetry: () {},
            builder: (_) {
              builderRan = true;
              return const Text('DATA');
            },
          ),
        ),
      );

      expect(find.text('No products match these filters.'), findsOneWidget);
      expect(builderRan, isFalse, reason: 'builder must not run when empty');
    });

    testWidgets('builds the data when nothing else applies', (tester) async {
      await tester.pumpWidget(
        _host(
          AsyncView(
            isLoading: false,
            error: null,
            isEmpty: false,
            emptyMessage: 'Nothing here.',
            onRetry: () {},
            builder: (_) => const Text('DATA'),
          ),
        ),
      );

      expect(find.text('DATA'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Nothing here.'), findsNothing);
    });

    testWidgets('loading outranks an error left over from a retry',
        (tester) async {
      // The realistic retry: the previous error is still held while the next
      // attempt is in flight. Showing the stale error would flash.
      await tester.pumpWidget(
        _host(
          AsyncView(
            isLoading: true,
            error: 'Stale failure from the last attempt.',
            isEmpty: false,
            emptyMessage: 'Nothing here.',
            onRetry: () {},
            builder: (_) => const Text('DATA'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Stale failure from the last attempt.'), findsNothing);
    });

    testWidgets('an error outranks the empty state', (tester) async {
      // isEmpty is often true on a failed first load. Reporting "no products"
      // when the real story is "the request failed" would be a lie.
      await tester.pumpWidget(
        _host(
          AsyncView(
            isLoading: false,
            error: 'Could not reach the server.',
            isEmpty: true,
            emptyMessage: 'No products match these filters.',
            onRetry: () {},
            builder: (_) => const Text('DATA'),
          ),
        ),
      );

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('No products match these filters.'), findsNothing);
    });
  });
}
