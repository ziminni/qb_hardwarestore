import 'dart:typed_data';

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/system_admin_service.dart';
import 'package:client/features/admin/views/admin_backup_restore_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 1100),
  List<SystemBackupSnapshot> snapshots = const [],
  Future<PickedBackupFile?> Function()? pickBackupFile,
  SystemAdminService? service,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final auth = AuthViewmodel(AuthRepository(AuthService()))
    ..user = const User(
      id: 1,
      username: 'admin',
      email: 'admin@qbhardware.com',
      fullName: 'Ada Min',
      role: Role(id: 1, name: 'admin', displayName: 'Admin'),
      isActive: true,
    );

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: AdminBackupRestorePage(
          initialSnapshots: snapshots,
          pickBackupFile: pickBackupFile,
          service: service,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('backup & restore route is fenced to Admin only', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: AppAreas.admin,
        location: AppRoutes.adminBackupRestore,
      ),
      isNull,
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: AppAreas.sales,
        location: AppRoutes.adminBackupRestore,
      ),
      AppRoutes.salesDashboard,
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: AppAreas.inventory,
        location: AppRoutes.adminBackupRestore,
      ),
      AppRoutes.inventoryDashboard,
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: AppAreas.pos,
        location: AppRoutes.adminBackupRestore,
      ),
      AppRoutes.posDashboard,
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: AppAreas.bodega,
        location: AppRoutes.adminBackupRestore,
      ),
      AppRoutes.bodegaPickups,
    );
  });

  testWidgets('renders cleanly on wide and narrow viewports with no overflow', (
    tester,
  ) async {
    for (final size in const [Size(1440, 1000), Size(760, 900)]) {
      await _pump(tester, size: size);
      expect(find.text('Backup & Restore'), findsOneWidget);
      expect(find.text('Create backup'), findsOneWidget);
      expect(find.text('Restore system'), findsOneWidget);
      expect(find.text('Awaiting backup API'), findsOneWidget);
      expect(
        find.textContaining('No server backups recorded yet'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'create backup opens manifest preview dialog with note & format',
    (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Data dump (.sql)'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Backup note (optional)'),
        'Pre-month-end close',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('backup-create-button')));
      await tester.pumpAndSettle();

      expect(find.text('Create system backup'), findsOneWidget);
      expect(find.text('Data dump (.sql)'), findsWidgets);
      expect(find.text('Pre-month-end close'), findsWidgets);
      // Honest scope copy: the snapshot is a JSON data fixture, media excluded.
      expect(
        find.textContaining('Uploaded media files are never included'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'restore stays gated until archive is picked, both checks ticked, and RESTORE typed',
    (tester) async {
      await _pump(
        tester,
        pickBackupFile: () async => PickedBackupFile(
          name: 'pos-20261119-2200.dump',
          sizeBytes: 4 * 1024 * 1024,
          bytes: Uint8List.fromList(const [1, 2, 3]),
        ),
      );

      FilledButton restoreButton() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('backup-restore-button')),
      );

      // Initially disabled with no file and unchecked safety boxes.
      expect(restoreButton().onPressed, isNull);

      // Pick backup archive.
      await tester.tap(find.byKey(const ValueKey('backup-pick-file')));
      await tester.pumpAndSettle();
      expect(find.text('pos-20261119-2200.dump'), findsOneWidget);
      expect(find.text('4.0 MB'), findsOneWidget);
      expect(restoreButton().onPressed, isNull);

      // Tick first safety check only -> still disabled.
      await tester.tap(find.byKey(const ValueKey('backup-check-recent')));
      await tester.pumpAndSettle();
      expect(restoreButton().onPressed, isNull);

      // Tick second safety check -> Restore button unlocks.
      await tester.tap(find.byKey(const ValueKey('backup-check-shifts')));
      await tester.pumpAndSettle();
      expect(restoreButton().onPressed, isNotNull);

      // Open high-safety confirmation dialog.
      await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
      await tester.pumpAndSettle();
      expect(find.text('Confirm system restore'), findsOneWidget);

      FilledButton confirmSubmit() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('backup-restore-confirm-submit')),
      );
      expect(confirmSubmit().onPressed, isNull);

      // Lowercase does not unlock.
      await tester.enterText(
        find.byKey(const ValueKey('backup-restore-confirm-input')),
        'restore',
      );
      await tester.pumpAndSettle();
      expect(confirmSubmit().onPressed, isNull);

      // Exact RESTORE unlocks confirmation.
      await tester.enterText(
        find.byKey(const ValueKey('backup-restore-confirm-input')),
        'RESTORE',
      );
      await tester.pumpAndSettle();
      expect(confirmSubmit().onPressed, isNotNull);
    },
  );

  testWidgets('failed restore shows the server error, never a fake success', (
    tester,
  ) async {
    final fakeService = _FakeBackupAdminService()
      ..restoreError = 'This server has no such backup.';
    final fileBytes = Uint8List.fromList(const [1, 2, 3]);
    await _pump(
      tester,
      service: fakeService,
      pickBackupFile: () async => PickedBackupFile(
        name: 'pos-20261119-2200.dump',
        sizeBytes: 2048,
        bytes: fileBytes,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('backup-pick-file')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup-check-recent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup-check-shifts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup-restore-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('backup-restore-confirm-input')),
      'RESTORE',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('backup-restore-confirm-submit')),
    );
    await tester.pumpAndSettle();

    // A local file restore uploads its bytes, and a refusal is shown verbatim.
    expect(fakeService.lastRestoreBytes, fileBytes);
    expect(
      find.textContaining('Restore failed: This server has no such backup.'),
      findsOneWidget,
    );
  });

  testWidgets('backup history supports search and source filter chips', (
    tester,
  ) async {
    final snapshots = [
      SystemBackupSnapshot(
        id: 'b1',
        filename: 'qb-manual-20261119.dump',
        createdAt: DateTime(2026, 11, 19, 9, 30),
        sizeBytes: 3200000,
        format: '.dump',
        origin: BackupOrigin.manual,
        createdBy: 'Ada Min',
        includesMedia: true,
        note: 'Pre-audit snapshot',
      ),
      SystemBackupSnapshot(
        id: 'b2',
        filename: 'qb-nightly-20261118.dump',
        createdAt: DateTime(2026, 11, 18, 2, 0),
        sizeBytes: 2950000,
        format: '.dump',
        origin: BackupOrigin.scheduled,
        createdBy: 'System scheduler',
        note: 'Nightly automatic',
      ),
    ];

    await _pump(tester, snapshots: snapshots);

    expect(find.text('qb-manual-20261119.dump'), findsOneWidget);
    expect(find.text('qb-nightly-20261118.dump'), findsOneWidget);

    // Filter by Scheduled source.
    final scheduledChip = find.descendant(
      of: find.byType(FilterBar),
      matching: find.text('Scheduled'),
    );
    await tester.ensureVisible(scheduledChip);
    await tester.tap(scheduledChip);
    await tester.pumpAndSettle();
    expect(find.text('qb-nightly-20261118.dump'), findsOneWidget);
    expect(find.text('qb-manual-20261119.dump'), findsNothing);

    // Reset to All and search by note.
    final allChip = find.descendant(
      of: find.byType(FilterBar),
      matching: find.text('All'),
    );
    await tester.ensureVisible(allChip);
    await tester.tap(allChip);
    await tester.pumpAndSettle();
    final searchField = find.descendant(
      of: find.byType(FilterBar),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(searchField);
    await tester.enterText(searchField, 'Pre-audit');
    await tester.pumpAndSettle();
    expect(find.text('qb-manual-20261119.dump'), findsOneWidget);
    expect(find.text('qb-nightly-20261118.dump'), findsNothing);
  });

  testWidgets(
    'creates backup, updates schedule, and restores snapshot via backend service',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeService = _FakeBackupAdminService();
      final auth = AuthViewmodel(AuthRepository(AuthService()))
        ..user = const User(
          id: 1,
          username: 'admin',
          email: 'admin@qbhardware.com',
          fullName: 'Ada Min',
          role: Role(id: 1, name: 'admin', displayName: 'Admin'),
          isActive: true,
        );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: auth,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: AdminBackupRestorePage(service: fakeService),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Live server sync'), findsOneWidget);
      expect(find.text('Synced with server'), findsOneWidget);

      // Create a new backup on the server.
      await tester.tap(find.byKey(const ValueKey('backup-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('backup-confirm-create-button')),
      );
      await tester.pumpAndSettle();

      expect(fakeService.createdCount, 1);
      expect(find.text('qb-pos-backup-live.dump'), findsOneWidget);

      // Update schedule frequency -> syncs with backend service.
      final weeklyChip = find.text('Weekly');
      await tester.ensureVisible(weeklyChip);
      await tester.tap(weeklyChip);
      await tester.pumpAndSettle();
      expect(fakeService.lastFrequency, 'Weekly');

      // Trigger restore from backup history row.
      final restoreRowBtn = find.widgetWithText(TextButton, 'Restore');
      await tester.ensureVisible(restoreRowBtn);
      await tester.tap(restoreRowBtn);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('backup-restore-confirm-input')),
        'RESTORE',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('backup-restore-confirm-submit')),
      );
      await tester.pumpAndSettle();

      expect(fakeService.restoredBackupId, 'bk-live-1');
    },
  );
}

class _FakeBackupAdminService extends SystemAdminService {
  int createdCount = 0;
  String lastFrequency = 'Daily';
  int lastRetention = 14;
  String? restoredBackupId;
  Uint8List? lastRestoreBytes;
  String? restoreError;
  final List<SystemBackupSnapshot> _snapshots = [];

  @override
  Future<BackupManifestPayload> fetchBackups() async {
    return BackupManifestPayload(
      schedule: BackupScheduleState(
        frequency: lastFrequency,
        retentionCount: lastRetention,
      ),
      snapshots: [..._snapshots],
    );
  }

  @override
  Future<SystemBackupSnapshot> createBackup({
    required String format,
    required bool includeMedia,
    required bool includeAuditLogs,
    String note = '',
  }) async {
    createdCount++;
    final snap = SystemBackupSnapshot(
      id: 'bk-live-$createdCount',
      filename: 'qb-pos-backup-live$format',
      createdAt: DateTime(2026, 11, 20, 2, 0),
      sizeBytes: 24576,
      format: format,
      origin: BackupOrigin.manual,
      createdBy: 'Ada Min',
      includesMedia: includeMedia,
      note: note,
    );
    _snapshots.insert(0, snap);
    return snap;
  }

  @override
  Future<BackupScheduleState> updateBackupSchedule({
    required String frequency,
    required int retentionCount,
  }) async {
    lastFrequency = frequency;
    lastRetention = retentionCount;
    return BackupScheduleState(
      frequency: frequency,
      retentionCount: retentionCount,
    );
  }

  @override
  Future<void> restoreBackup({
    String? backupId,
    String? filename,
    Uint8List? bytes,
  }) async {
    restoredBackupId = backupId ?? filename;
    lastRestoreBytes = bytes;
    if (restoreError case final message?) {
      throw SystemAdminServiceException(message);
    }
  }
}
