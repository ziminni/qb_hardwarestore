@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/network/paged.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/audit_log.dart';
import 'package:client/data/repositories/audit_log_repository.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/audit_log_service.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/views/audit_logs_page.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The fallback visual check (00-shared/VERIFY.md, fallback 3) for card A6: the
/// Audit logs screen (list, empty, error, permission denied) and the Settings
/// card, rendered with the REAL fonts and the REAL theme into the SDD folder.
///
/// Same opt-in mechanism as F3's gallery, so the normal suite never fails on a
/// font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/admin/ac6_audit_settings_golden_test.dart
/// ```
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  // Absolute on purpose: the PNGs belong to the SDD folder in the main
  // checkout, not next to this test inside the card's worktree.
  final goldenDir = Directory(
    '/home/yaji/projects/qb_ecosystem/qb_pos_inventory_system/'
    '.superpowers/sdd/ui-refresh/goldens',
  );

  setUpAll(() async {
    goldenDir.createSync(recursive: true);
    await _loadFont('Cinzel', const [
      'Cinzel-Regular.ttf',
      'Cinzel-Medium.ttf',
      'Cinzel-Bold.ttf',
    ]);
    await _loadFont('OpenSans', const [
      'OpenSans-Regular.ttf',
      'OpenSans-Medium.ttf',
      'OpenSans-Bold.ttf',
    ]);
    // Icons: the test harness does not load the Material icon font, so every
    // Icon would be a box in the PNG.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
  });

  for (final entry in const [
    ('1440', Size(1440, 900)),
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('audit logs list at ${entry.$1} px', (tester) async {
      await _pump(
        tester,
        entry.$2,
        AuditLogsPage(repository: _StubAuditLogRepository(_trail)),
      );
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/a6-audit-logs-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  for (final state in const [
    ('empty', null),
    ('error', 'The audit trail could not be loaded.'),
    ('permission-denied', 'No permission to view the audit trail.'),
  ]) {
    testWidgets('audit logs ${state.$1} at 760 px', (tester) async {
      await _pump(
        tester,
        const Size(760, 900),
        AuditLogsPage(
          repository: _StubAuditLogRepository(
            state.$1 == 'empty' ? const [] : _trail,
            failure: state.$2,
          ),
        ),
      );
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/a6-audit-logs-${state.$1}-760.png'),
        ),
      );
    }, skip: !enabled);
  }

  for (final entry in const [
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('settings at ${entry.$1} px', (tester) async {
      await _pump(tester, entry.$2, const SettingsPage());
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/a6-settings-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }
}

const _goldenKey = ValueKey('AuditSettingsGolden');

/// Answers page 1 from memory; no PNG depends on a server.
class _StubAuditLogRepository extends AuditLogRepository {
  _StubAuditLogRepository(this.rows, {this.failure});

  final List<AuditLog> rows;
  final String? failure;

  @override
  Future<Paged<AuditLog>> fetchAuditLogs({int page = 1}) async {
    final failure = this.failure;
    if (failure != null) throw AuditLogServiceException(failure);
    return Paged<AuditLog>(
      items: rows,
      // A trail longer than one page, so the pager shows both its buttons in a
      // state a reader would actually meet.
      total: 137,
      hasMore: true,
    );
  }
}

/// A working day's trail: sign in, sales, a stock adjustment and a deletion,
/// with one long email and one long description so the columns prove they
/// shorten instead of pushing the row wider.
final List<AuditLog> _trail = [
  _log(
    id: 9,
    email: 'ana.lopez@qb.local',
    code: 'SALE',
    description: 'Completed sale TRX-20261030-0004 for Dela Cruz Construction',
    at: DateTime(2026, 10, 30, 15, 42),
  ),
  _log(
    id: 8,
    email: 'maria.santos@qb.local',
    code: 'PAYMENT',
    description: 'Recorded a partial payment on account C-0142',
    at: DateTime(2026, 10, 30, 14, 14),
  ),
  _log(
    id: 7,
    email: 'ben.cruz@qb.local',
    code: 'STOCK_ADJUST',
    description: 'Adjusted PVC Pipe 2 in x 3 m stock by 12 pieces',
    at: DateTime(2026, 10, 30, 13, 5),
  ),
  _log(
    id: 6,
    email: 'rosario.delacruz.mendoza@qb.local',
    code: 'UPDATE',
    description: 'Changed the reorder threshold for Portland Cement 40 kg',
    at: DateTime(2026, 10, 30, 11, 30),
  ),
  _log(
    id: 5,
    email: 'ana.lopez@qb.local',
    code: 'RECEIPT',
    description: 'Received 120 bags of Portland Cement 40 kg from Holcim',
    at: DateTime(2026, 10, 30, 10, 12),
  ),
  _log(
    id: 4,
    email: 'admin@qb.local',
    code: 'DELETE',
    description: 'Deleted a duplicate product entry for Marine Plywood 3/4 in',
    at: DateTime(2026, 10, 30, 9, 48),
  ),
  _log(
    id: 3,
    email: 'admin@qb.local',
    code: 'CREATE',
    description: 'Created the account for rosario.delacruz.mendoza@qb.local',
    at: DateTime(2026, 10, 30, 9, 2),
  ),
  _log(
    id: 2,
    email: 'maria.santos@qb.local',
    code: 'LOGIN',
    description: 'Signed in at POS Terminal 02',
    at: DateTime(2026, 10, 30, 8, 0),
  ),
  _log(
    id: 1,
    email: 'ben.cruz@qb.local',
    code: 'LOGOUT',
    description: 'Signed out at POS Terminal 01',
    at: DateTime(2026, 10, 29, 18, 30),
  ),
];

AuditLog _log({
  required int id,
  required String email,
  required String code,
  required String description,
  required DateTime at,
}) => AuditLog(
  id: id,
  userEmail: email,
  actionType: code,
  description: description,
  ipAddress: '10.0.0.5',
  timestamp: at,
);

Future<void> _pump(WidgetTester tester, Size size, Widget page) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: RepaintBoundary(
          key: _goldenKey,
          child: ColoredBox(
            color: AppTheme.lightTheme.colorScheme.surface,
            child: page,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The logo is an asset image and image decoding does not run inside the fake
  // async zone: without this the brand renders as empty space. 42 is the full
  // sidebar's size, 40 the rail's.
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(_goldenKey));
    for (final logoSize in const [40, 42]) {
      await precacheImage(
        ResizeImage.resizeIfNeeded(
          logoSize,
          logoSize,
          const AssetImage(AppAssets.logo),
        ),
        context,
      );
    }
  });
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: 'a layout overflow would paint the yellow stripes into the PNG',
  );
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = await File('assets/fonts/$file').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _loadFontFile(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// The running Flutter SDK, found from the environment or from the dart binary
/// that is executing this test.
String? _flutterSdkFile(String relativePath) {
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      '$root/$relativePath',
  ];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 6; depth++) {
    candidates.add('${dir.path}/$relativePath');
    dir = dir.parent;
  }
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
