// Card A6 (UI refresh): the Audit logs screen becomes a readable, filterable
// list instead of a flat table of raw server codes.
//
// These tests pin the four things that change:
//   * an action code renders as words ("Sale", not "SALE"),
//   * a timestamp renders through `formatDateTime` (D6),
//   * search and the action chips narrow the LOADED page, and the page says so
//     out loud (the server paginates; a client filter cannot reach page 2),
//   * the server pagination still works: Next fetches the next page and a
//     failure on that page keeps the rows already read.
//
// The empty and error states stay pinned by `audit_logs_live_test.dart`.

import 'package:client/core/network/paged.dart';
import 'package:client/data/models/audit_log.dart';
import 'package:client/data/repositories/audit_log_repository.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/audit_log_service.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/views/audit_logs_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Answers page N from [pages] and can fail one page on demand.
class _PagedAuditLogRepository extends AuditLogRepository {
  _PagedAuditLogRepository(this.pages);

  /// Page number to its rows. A page outside this map is empty.
  final Map<int, List<AuditLog>> pages;

  /// Pages that fail with [failure] instead of returning rows.
  final Set<int> failingPages = {};

  String failure = 'The audit trail could not be loaded.';

  final List<int> requested = [];

  @override
  Future<Paged<AuditLog>> fetchAuditLogs({int page = 1}) async {
    requested.add(page);
    if (failingPages.contains(page)) throw AuditLogServiceException(failure);
    return Paged<AuditLog>(
      items: pages[page] ?? const <AuditLog>[],
      total: pages.values.fold<int>(0, (sum, rows) => sum + rows.length),
      hasMore: pages.keys.any((loaded) => loaded > page),
    );
  }
}

AuditLog _log({
  required int id,
  required String userEmail,
  required String actionType,
  required String description,
  required DateTime timestamp,
  String? ipAddress = '10.0.0.5',
}) => AuditLog(
  id: id,
  userEmail: userEmail,
  actionType: actionType,
  description: description,
  ipAddress: ipAddress,
  timestamp: timestamp,
);

/// Two pages: page 1 holds a sale and a stock adjustment, page 2 an older sign
/// in. Enough rows to tell the three action labels apart.
_PagedAuditLogRepository _twoPages() => _PagedAuditLogRepository({
  1: [
    _log(
      id: 3,
      userEmail: 'ana.lopez@qb.local',
      actionType: 'SALE',
      description: 'Completed sale TRX-20261030-0001',
      timestamp: DateTime(2026, 10, 22, 14, 5),
    ),
    _log(
      id: 2,
      userEmail: 'ben.cruz@qb.local',
      actionType: 'STOCK_ADJUST',
      description: 'Adjusted PVC pipe stock by 4',
      timestamp: DateTime(2026, 10, 22, 9, 7),
    ),
  ],
  2: [
    _log(
      id: 1,
      userEmail: 'maria.santos@qb.local',
      actionType: 'LOGIN',
      description: 'Signed in at POS Terminal 02',
      timestamp: DateTime(2026, 10, 21, 8, 0),
    ),
  ],
});

Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

Future<void> _pump(
  WidgetTester tester,
  AuditLogRepository repository, {
  Size size = const Size(1600, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(AuditLogsPage(repository: repository)));
  await tester.pumpAndSettle();
}

/// One full server page: 50 actions, the DRF `PAGE_SIZE` the endpoint uses. A
/// short page hides the layout defect this file pins (the list grows past the
/// window and takes the pager with it).
_PagedAuditLogRepository _fullPage() => _PagedAuditLogRepository({
  1: [
    for (var index = 1; index <= 50; index++)
      _log(
        id: index,
        userEmail: 'staff$index@qb.local',
        actionType: 'SALE',
        description:
            'Completed sale TRX-20261030-${index.toString().padLeft(4, '0')}',
        timestamp: DateTime(
          2026,
          10,
          22,
          14,
          5,
        ).subtract(Duration(minutes: index)),
      ),
  ],
});

/// A row badge with [label]. Chips share the same words, so expectations on a
/// badge are scoped to the badge and expectations on a chip to the bar.
Finder _badge(String label) =>
    find.descendant(of: find.byType(StatusBadge), matching: find.text(label));

/// A chip or a row badge can share a label, so chip taps are scoped to the bar.
Finder _chip(String label) =>
    find.descendant(of: find.byType(FilterBar), matching: find.text(label));

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(FilterBar),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AuditLogsPage actions', () {
    testWidgets('an action code reads as words', (tester) async {
      await _pump(tester, _twoPages());

      // Scoped to the badges: the action chips carry the same words.
      expect(_badge('Sale'), findsOneWidget);
      expect(_badge('Stock adjustment'), findsOneWidget);
      expect(
        find.text('SALE'),
        findsNothing,
        reason: 'a raw server code is not an admin-facing label',
      );
      expect(find.text('STOCK_ADJUST'), findsNothing);
    });

    testWidgets('a row opens the whole entry, with the IP address', (
      tester,
    ) async {
      await _pump(tester, _twoPages());

      await tester.tap(find.text('ana.lopez@qb.local'));
      await tester.pumpAndSettle();

      expect(find.text('Audit entry'), findsOneWidget);
      // Scoped to the dialog: the same description is on the row behind it.
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Completed sale TRX-20261030-0001'),
        ),
        findsOneWidget,
      );
      expect(find.text('IP address'), findsOneWidget);
      expect(find.text('10.0.0.5'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Audit entry'), findsNothing);
    });

    testWidgets('an entry with no IP address says so instead of a dash', (
      tester,
    ) async {
      await _pump(
        tester,
        _PagedAuditLogRepository({
          1: [
            _log(
              id: 1,
              userEmail: 'ben.cruz@qb.local',
              actionType: 'LOGIN',
              description: 'Signed in at POS Terminal 02',
              timestamp: DateTime(2026, 10, 22, 9, 7),
              ipAddress: null,
            ),
          ],
        }),
      );

      await tester.tap(find.text('ben.cruz@qb.local'));
      await tester.pumpAndSettle();

      expect(find.text('Not recorded'), findsOneWidget);
    });

    testWidgets('a timestamp uses the one date format', (tester) async {
      await _pump(tester, _twoPages());

      expect(find.text('Oct 22, 2026, 2:05 PM'), findsOneWidget);
      expect(
        find.text('10/22/2026 14:05'),
        findsNothing,
        reason: 'D6: one date format for the whole app',
      );
    });
  });

  group('AuditLogsPage filters', () {
    testWidgets('the page says the filters cover only the loaded page', (
      tester,
    ) async {
      await _pump(tester, _twoPages());

      expect(
        find.text('Filters search the actions on this page only.'),
        findsOneWidget,
      );
    });

    testWidgets('search narrows the loaded page', (tester) async {
      await _pump(tester, _twoPages());
      await _search(tester, 'ben');

      expect(find.text('ben.cruz@qb.local'), findsOneWidget);
      expect(find.text('ana.lopez@qb.local'), findsNothing);
    });

    testWidgets('an action chip narrows the loaded page', (tester) async {
      await _pump(tester, _twoPages());
      await tester.tap(_chip('Stock adjustment'));
      await tester.pumpAndSettle();

      expect(find.text('ben.cruz@qb.local'), findsOneWidget);
      expect(find.text('ana.lopez@qb.local'), findsNothing);
    });

    testWidgets('a filter that hides everything says so', (tester) async {
      await _pump(tester, _twoPages());
      await _search(tester, 'nothing matches this');

      expect(find.text('No audit logs match these filters.'), findsOneWidget);
      expect(
        find.text('No audit logs recorded.'),
        findsNothing,
        reason: 'a filtered list is not an empty audit trail',
      );
    });
  });

  group('AuditLogsPage pagination', () {
    testWidgets('Next reads the next server page', (tester) async {
      final repository = _twoPages();
      await _pump(tester, repository);

      expect(find.text('Page 1'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(repository.requested, [1, 2]);
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('maria.santos@qb.local'), findsOneWidget);
      expect(
        find.text('ana.lopez@qb.local'),
        findsNothing,
        reason: 'page 2 replaces page 1: it is not an append',
      );
    });

    testWidgets('a failed next page keeps the rows already read', (
      tester,
    ) async {
      final repository = _twoPages()..failingPages.add(2);
      await _pump(tester, repository);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(repository.failure, isNotNull);
      expect(
        find.text('ana.lopez@qb.local'),
        findsOneWidget,
        reason: 'a failed refresh must not blank the audit rows on screen',
      );
    });

    testWidgets('a new page drops a filter the new page cannot show', (
      tester,
    ) async {
      // The chips are built from the page on screen, so an action kept across
      // pages can vanish from the bar and leave a filter nothing names.
      await _pump(tester, _twoPages());
      await tester.tap(_chip('Stock adjustment'));
      await tester.pumpAndSettle();
      expect(find.text('ana.lopez@qb.local'), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Page 2'), findsOneWidget);
      expect(
        tester.widget<FilterBar>(find.byType(FilterBar)).selected,
        'All',
        reason: 'page 2 holds no stock adjustment, so its chip cannot exist',
      );
      expect(
        find.text('maria.santos@qb.local'),
        findsOneWidget,
        reason: 'the new page must be shown whole, not hidden by a stale chip',
      );
    });
  });

  group('AuditLogsPage layout', () {
    // A full page of 50 actions is the shape that breaks: in a page scroll view
    // every row builds and the pager sits below the fold.
    for (final size in const [
      Size(1440, 900),
      Size(1100, 900),
      Size(760, 900),
      Size(1366, 768),
    ]) {
      testWidgets(
        'a full page of logs fits ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pump(tester, _fullPage(), size: size);

          expect(tester.takeException(), isNull);
          expect(find.text('Page 1'), findsOneWidget);
          expect(find.text('staff1@qb.local'), findsOneWidget);
          expect(
            tester.getRect(find.text('Next')).bottom,
            lessThanOrEqualTo(size.height),
            reason: 'the pager stays on screen; only the rows scroll',
          );
        },
      );
    }
  });
}
