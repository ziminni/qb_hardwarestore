import 'dart:typed_data';

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/data/services/system_admin_service.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Origin of a server backup snapshot.
enum BackupOrigin {
  manual('Manual'),
  scheduled('Scheduled');

  const BackupOrigin(this.label);
  final String label;
}

/// Extension chosen for the file name. Both options hold the same Django
/// `dumpdata` JSON fixture — the backend never writes a native SQL dump.
enum BackupFormat {
  customDump('Data dump (.dump)', '.dump', 'Recommended'),
  plainSql('Data dump (.sql)', '.sql', 'Same contents');

  const BackupFormat(this.label, this.extension, this.hint);
  final String label;
  final String extension;
  final String hint;
}

/// A single backup snapshot record, structured to bind directly to a future
/// `GET /api/v1/system/backups/` payload without reshaping the UI.
class SystemBackupSnapshot {
  const SystemBackupSnapshot({
    required this.id,
    required this.filename,
    required this.createdAt,
    required this.sizeBytes,
    required this.format,
    required this.origin,
    required this.createdBy,
    this.includesMedia = false,
    this.note = '',
  });

  final String id;
  final String filename;
  final DateTime createdAt;
  final int sizeBytes;
  final String format;
  final BackupOrigin origin;
  final String createdBy;
  final bool includesMedia;
  final String note;
}

/// A locally selected backup file ready for upload.
class PickedBackupFile {
  const PickedBackupFile({
    required this.name,
    required this.sizeBytes,
    this.path,
    this.bytes,
  });

  final String name;
  final int sizeBytes;
  final String? path;

  /// The file contents, uploaded as multipart `file`. Restore must send the
  /// bytes: a name alone lets the server pick a different same-name snapshot.
  final Uint8List? bytes;

  String get detectedExtension {
    final lower = name.toLowerCase();
    if (lower.endsWith('.tar.gz')) return '.tar.gz';
    final dot = lower.lastIndexOf('.');
    if (dot < 0 || dot == lower.length - 1) return 'archive';
    return lower.substring(dot);
  }
}

/// Admin System Backup & Restore workspace (`/admin/backup-restore`).
///
/// The server stores snapshots as Django JSON data fixtures (`dumpdata`), not
/// native `pg_dump`/`.sql` dumps, and media files are never part of them. A
/// restore replaces database records only and needs every cashier off the POS.
class AdminBackupRestorePage extends StatefulWidget {
  const AdminBackupRestorePage({
    super.key,
    this.initialSnapshots = const [],
    this.pickBackupFile,
    this.service,
  });

  /// Optional snapshots injected by tests or a future viewmodel.
  final List<SystemBackupSnapshot> initialSnapshots;

  /// Optional file picker override for tests.
  final Future<PickedBackupFile?> Function()? pickBackupFile;

  /// Optional backend service override for tests.
  final SystemAdminService? service;

  /// Server-side upload limit for a restore file.
  static const int maxRestoreUploadBytes = 512 * 1024 * 1024;

  @override
  State<AdminBackupRestorePage> createState() => _AdminBackupRestorePageState();
}

class _AdminBackupRestorePageState extends State<AdminBackupRestorePage> {
  late final SystemAdminService _service =
      widget.service ?? const SystemAdminService();

  late List<SystemBackupSnapshot> _snapshots = [...widget.initialSnapshots];
  bool _serverConnected = false;

  // ---- Create backup options
  bool _includeAuditLogs = true;
  BackupFormat _format = BackupFormat.customDump;
  final TextEditingController _noteController = TextEditingController();

  // ---- Restore state
  PickedBackupFile? _selectedFile;
  bool _confirmedRecentBackup = false;
  bool _confirmedShiftsClosed = false;
  bool _pickingFile = false;

  // ---- History search & filter
  final TextEditingController _historySearchController =
      TextEditingController();
  String _historyQuery = '';
  String _originFilter = 'All';

  // ---- Schedule policy draft (UI preview)
  String _scheduleFrequency = 'Daily';
  int _retentionCount = 14;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFromServer();
    });
  }

  Future<void> _loadFromServer() async {
    try {
      final manifest = await _service.fetchBackups();
      if (!mounted) return;
      setState(() {
        _serverConnected = true;
        _scheduleFrequency = manifest.schedule.frequency;
        _retentionCount = manifest.schedule.retentionCount;
        if (widget.initialSnapshots.isEmpty || manifest.snapshots.isNotEmpty) {
          _snapshots = manifest.snapshots;
        }
      });
    } catch (_) {
      // Offline / uninitialized transport in isolated widget tests: keep
      // initialSnapshots intact.
    }
  }

  Future<void> _syncSchedule() async {
    try {
      final saved = await _service.updateBackupSchedule(
        frequency: _scheduleFrequency,
        retentionCount: _retentionCount,
      );
      if (!mounted) return;
      setState(() {
        _serverConnected = true;
        _scheduleFrequency = saved.frequency;
        _retentionCount = saved.retentionCount;
      });
    } catch (_) {
      // Ignore in offline widget tests.
    }
  }

  Future<void> _runCreateBackup(String note) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await _service.createBackup(
        format: _format.extension,
        includeMedia: false,
        includeAuditLogs: _includeAuditLogs,
        note: note,
      );
      if (!mounted) return;
      setState(() {
        _serverConnected = true;
        _snapshots = [created, ..._snapshots];
        _noteController.clear();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Created server backup ${created.filename} (${_formatBytes(created.sizeBytes)}).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create backup on server: $e')),
      );
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _historySearchController.dispose();
    super.dispose();
  }

  List<SystemBackupSnapshot> get _filteredSnapshots {
    final q = _historyQuery.trim().toLowerCase();
    return [
      for (final snap in _snapshots)
        if ((_originFilter == 'All' || snap.origin.label == _originFilter) &&
            (q.isEmpty ||
                '${snap.filename} ${snap.createdBy} ${snap.note} ${snap.format}'
                    .toLowerCase()
                    .contains(q)))
          snap,
    ];
  }

  bool get _canRestore =>
      _selectedFile != null && _confirmedRecentBackup && _confirmedShiftsClosed;

  Future<void> _pickFile() async {
    setState(() => _pickingFile = true);
    try {
      PickedBackupFile? picked;
      final customPicker = widget.pickBackupFile;
      if (customPicker != null) {
        picked = await customPicker();
      } else {
        const typeGroup = XTypeGroup(
          label: 'Database backup',
          extensions: <String>['dump', 'sql', 'json'],
        );
        final file = await openFile(acceptedTypeGroups: const [typeGroup]);
        if (file != null) {
          final size = await file.length();
          if (size > AdminBackupRestorePage.maxRestoreUploadBytes) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Backup files larger than 512 MB cannot be uploaded.',
                ),
              ),
            );
            return;
          }
          picked = PickedBackupFile(
            name: file.name,
            sizeBytes: size,
            path: file.path,
            bytes: await file.readAsBytes(),
          );
        }
      }
      if (!mounted || picked == null) return;
      setState(() => _selectedFile = picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the file picker on this device.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  void _clearSelectedFile() {
    setState(() {
      _selectedFile = null;
      _confirmedRecentBackup = false;
      _confirmedShiftsClosed = false;
    });
  }

  /// Saves a server snapshot to disk. Bytes come from the API, not the name.
  Future<void> _downloadSnapshot(SystemBackupSnapshot snap) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _service.downloadBackup(snap.id);
      final location = await getSaveLocation(suggestedName: snap.filename);
      // Cancelled at the Save dialog: nothing was asked of us, no error.
      if (location == null) return;
      await XFile.fromData(
        bytes,
        mimeType: 'application/json',
        name: snap.filename,
      ).saveTo(location.path);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Saved ${snap.filename}.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not download ${snap.filename}: $e')),
      );
    }
  }

  Future<void> _openCreatePreview() {
    final note = _noteController.text.trim();
    final now = appClock.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final filename = 'qb-pos-backup-$stamp${_format.extension}';

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final p = AppPalette.of(dialogContext);
        return AppDialog(
          icon: Icons.cloud_download_outlined,
          title: 'Create system backup',
          subtitle: 'Review the snapshot manifest before running.',
          width: 500,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DialogSectionLabel('Snapshot manifest'),
              _ManifestRow(label: 'File name', value: filename),
              _ManifestRow(label: 'Format', value: _format.label),
              _ManifestRow(
                label: 'Included data',
                value: [
                  'Database records (JSON)',
                  if (_includeAuditLogs) 'Audit logs',
                ].join(' · '),
              ),
              if (note.isNotEmpty) _ManifestRow(label: 'Note', value: note),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.selected,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(color: p.accent.withValues(alpha: 0.45)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: p.accentInk,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'The snapshot holds database records as a Django JSON '
                        'fixture. Uploaded media files are never included.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              key: const ValueKey('backup-confirm-create-button'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _runCreateBackup(note);
              },
              icon: const Icon(Icons.backup_outlined, size: 16),
              label: const Text('Create backup now'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openRestoreConfirmDialog({
    String? backupId,
    required String filename,
    required int sizeBytes,
    required String format,
    Uint8List? bytes,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _RestoreConfirmDialog(
        backupId: backupId,
        filename: filename,
        sizeBytes: sizeBytes,
        format: format,
        onConfirmRestore: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await _service.restoreBackup(
              backupId: backupId,
              filename: bytes == null ? null : filename,
              bytes: bytes,
            );
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 8),
                content: Text(
                  'Database restored from $filename. Keep all cashiers '
                  'stopped until they sign in again: sessions opened before '
                  'the restore may still hold old access tokens.',
                ),
              ),
            );
          } catch (e) {
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text('Restore failed: $e')),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final snapshots = _filteredSnapshots;
    final hasActiveHistoryFilter =
        _historyQuery.trim().isNotEmpty || _originFilter != 'All';

    return AdminSkeletonLayout(
      title: 'Backup & Restore',
      subtitle: 'Protect store records with snapshots and controlled restores.',
      selectedNavigationIndex: AppDestinations.indexOf(
        'admin.backup-restore',
        AppAreas.admin,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadinessBanner(serverConnected: _serverConnected),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumn = constraints.maxWidth >= 880;
              final createCard = _CreateBackupCard(
                includeAuditLogs: _includeAuditLogs,
                format: _format,
                noteController: _noteController,
                onIncludeAuditLogsChanged: (v) =>
                    setState(() => _includeAuditLogs = v),
                onFormatChanged: (v) => setState(() => _format = v),
                onCreatePressed: _openCreatePreview,
              );
              final restoreCard = _RestoreBackupCard(
                selectedFile: _selectedFile,
                pickingFile: _pickingFile,
                confirmedRecentBackup: _confirmedRecentBackup,
                confirmedShiftsClosed: _confirmedShiftsClosed,
                canRestore: _canRestore,
                onPickFile: _pickFile,
                onClearFile: _clearSelectedFile,
                onConfirmedRecentBackupChanged: (v) =>
                    setState(() => _confirmedRecentBackup = v),
                onConfirmedShiftsClosedChanged: (v) =>
                    setState(() => _confirmedShiftsClosed = v),
                onRestorePressed: () {
                  final file = _selectedFile;
                  if (file == null) return;
                  _openRestoreConfirmDialog(
                    filename: file.name,
                    sizeBytes: file.sizeBytes,
                    format: file.detectedExtension,
                    bytes: file.bytes,
                  );
                },
              );

              if (twoColumn) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: createCard),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: restoreCard),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  createCard,
                  const SizedBox(height: AppSpacing.lg),
                  restoreCard,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _SchedulePolicyCard(
            frequency: _scheduleFrequency,
            retentionCount: _retentionCount,
            serverConnected: _serverConnected,
            onFrequencyChanged: (v) {
              setState(() => _scheduleFrequency = v);
              _syncSchedule();
            },
            onRetentionChanged: (v) {
              setState(() => _retentionCount = v);
              _syncSchedule();
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.cardBackground,
              borderRadius: BorderRadius.circular(AppRadii.large),
              border: Border.all(color: p.border),
            ),
            child: FilterBar(
              searchController: _historySearchController,
              searchHint: 'Search backup filename, creator, or note',
              onSearchChanged: (value) => setState(() => _historyQuery = value),
              optionsLabel: 'Source',
              options: const ['All', 'Manual', 'Scheduled'],
              selected: _originFilter,
              onSelected: (chip) => setState(() => _originFilter = chip),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DataPanel<SystemBackupSnapshot>(
            title: 'Backup history',
            count: snapshots.length,
            rows: snapshots,
            emptyMessage: hasActiveHistoryFilter
                ? 'No backup snapshots match these filters.'
                : 'No server backups recorded yet. Snapshots created here or '
                      'by scheduled server jobs will appear here once the '
                      'backup API is reachable.',
            rowKey: (snap) => ValueKey('admin.backup.${snap.id}'),
            columns: [
              DataPanelColumn<SystemBackupSnapshot>(
                label: 'Snapshot',
                flex: 3,
                cell: (snap) => _SnapshotCell(snapshot: snap),
              ),
              DataPanelColumn<SystemBackupSnapshot>(
                label: 'Source',
                flex: 1,
                cell: (snap) => StatusBadge(
                  label: snap.origin.label,
                  tone: snap.origin == BackupOrigin.scheduled
                      ? StatusTone.info
                      : StatusTone.neutral,
                ),
              ),
              DataPanelColumn<SystemBackupSnapshot>(
                label: 'Size',
                flex: 1,
                numeric: true,
                cell: (snap) => Text(
                  _formatBytes(snap.sizeBytes),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
              ),
              DataPanelColumn<SystemBackupSnapshot>(
                label: 'Created',
                flex: 2,
                cell: (snap) => Text(
                  '${formatDate(snap.createdAt)} · ${snap.createdBy}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                ),
              ),
              DataPanelColumn<SystemBackupSnapshot>(
                label: 'Actions',
                flex: 2,
                cell: (snap) => Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 6,
                  children: [
                    TextButton.icon(
                      onPressed: () => _downloadSnapshot(snap),
                      style: TextButton.styleFrom(
                        backgroundColor: p.surfaceSunken,
                        foregroundColor: p.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: const Size(44, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.small),
                          side: BorderSide(color: p.border),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: Icon(
                        Icons.download_outlined,
                        size: 15,
                        color: p.accentInk,
                      ),
                      label: const Text('Download'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openRestoreConfirmDialog(
                        backupId: snap.id,
                        filename: snap.filename,
                        sizeBytes: snap.sizeBytes,
                        format: snap.format,
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: p.isDark
                            ? AppColors.error.withValues(alpha: 0.16)
                            : AppColors.errorTint,
                        foregroundColor: p.isDark
                            ? const Color(0xFFFCA5A5)
                            : AppColors.errorText,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: const Size(44, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.small),
                          side: BorderSide(
                            color: AppColors.error.withValues(alpha: 0.28),
                          ),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.restore_rounded, size: 15),
                      label: const Text('Restore'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadinessBanner extends StatelessWidget {
  const _ReadinessBanner({this.serverConnected = false});

  final bool serverConnected;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: p.accent.withValues(alpha: 0.45)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: p.selected,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    border: Border.all(color: p.accent.withValues(alpha: 0.45)),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 20,
                    color: p.accentInk,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'System backup workspace',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          StatusBadge(
                            label: serverConnected
                                ? 'Live server sync'
                                : 'Awaiting backup API',
                            tone: serverConnected
                                ? StatusTone.success
                                : StatusTone.info,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Snapshots are Django JSON data dumps stored on the '
                        'server. A restore replaces database records only — '
                        'media files are never included, and every cashier must '
                        'be off the POS while it runs.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateBackupCard extends StatelessWidget {
  const _CreateBackupCard({
    required this.includeAuditLogs,
    required this.format,
    required this.noteController,
    required this.onIncludeAuditLogsChanged,
    required this.onFormatChanged,
    required this.onCreatePressed,
  });

  final bool includeAuditLogs;
  final BackupFormat format;
  final TextEditingController noteController;
  final ValueChanged<bool> onIncludeAuditLogsChanged;
  final ValueChanged<BackupFormat> onFormatChanged;
  final VoidCallback onCreatePressed;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final ctaBg = p.isDark ? p.accent : AppColors.brandBlack;
    final ctaFg = p.isDark ? p.onAccent : AppColors.brandWhite;

    return Container(
      key: const ValueKey('backup-create-card'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const HexIconBadge(
                    icon: Icons.cloud_download_outlined,
                    size: 42,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create backup',
                          style: AppTextStyles.h3.copyWith(
                            fontSize: 18,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Capture a clean point-in-time snapshot of the store.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const DialogSectionLabel('Snapshot scope'),
              _ScopeOptionTile(
                title: 'Database records',
                subtitle:
                    'Always included: sales, inventory, users, shifts, payables and deliveries.',
                checked: true,
                locked: true,
                onChanged: null,
              ),
              const SizedBox(height: AppSpacing.sm),
              _ScopeOptionTile(
                title: 'Product images & media',
                subtitle: 'Back up uploaded files separately. This snapshot only saves database records.',
                checked: false,
                locked: true,
                onChanged: null,
              ),
              const SizedBox(height: AppSpacing.sm),
              _ScopeOptionTile(
                title: 'Audit logs archive',
                subtitle: 'Complete append-only admin and operational trail.',
                checked: includeAuditLogs,
                onChanged: onIncludeAuditLogsChanged,
              ),
              const SizedBox(height: AppSpacing.lg),
              const DialogSectionLabel('Output format'),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final option in BackupFormat.values)
                    ChoiceChip(
                      label: Text(option.label),
                      selected: format == option,
                      backgroundColor: p.surfaceSunken,
                      selectedColor: p.selected,
                      checkmarkColor: p.accentInk,
                      side: BorderSide(
                        color: format == option ? p.accent : p.border,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: format == option ? p.accentInk : p.textPrimary,
                      ),
                      onSelected: (_) => onFormatChanged(option),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: noteController,
                style: TextStyle(fontSize: 13.5, color: p.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Backup note (optional)',
                  hintText: 'e.g. Before month-end inventory count',
                  filled: true,
                  fillColor: p.surfaceSunken,
                  prefixIcon: const Icon(Icons.edit_note_rounded, size: 19),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
          FilledButton.icon(
            key: const ValueKey('backup-create-button'),
            onPressed: onCreatePressed,
            style: FilledButton.styleFrom(
              backgroundColor: ctaBg,
              foregroundColor: ctaFg,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: const Icon(Icons.backup_outlined, size: 18),
            label: const Text('Create & download backup'),
          ),
        ],
      ),
    );
  }
}

class _RestoreBackupCard extends StatelessWidget {
  const _RestoreBackupCard({
    required this.selectedFile,
    required this.pickingFile,
    required this.confirmedRecentBackup,
    required this.confirmedShiftsClosed,
    required this.canRestore,
    required this.onPickFile,
    required this.onClearFile,
    required this.onConfirmedRecentBackupChanged,
    required this.onConfirmedShiftsClosedChanged,
    required this.onRestorePressed,
  });

  final PickedBackupFile? selectedFile;
  final bool pickingFile;
  final bool confirmedRecentBackup;
  final bool confirmedShiftsClosed;
  final bool canRestore;
  final VoidCallback onPickFile;
  final VoidCallback onClearFile;
  final ValueChanged<bool> onConfirmedRecentBackupChanged;
  final ValueChanged<bool> onConfirmedShiftsClosedChanged;
  final VoidCallback onRestorePressed;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final file = selectedFile;
    final errorInk = p.isDark ? const Color(0xFFFCA5A5) : AppColors.errorText;
    final errorBg = p.isDark
        ? AppColors.error.withValues(alpha: 0.14)
        : AppColors.errorTint;

    return Container(
      key: const ValueKey('backup-restore-card'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: errorBg,
                      borderRadius: BorderRadius.circular(AppRadii.medium),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(
                      Icons.restore_page_outlined,
                      size: 22,
                      color: errorInk,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Restore system',
                          style: AppTextStyles.h3.copyWith(
                            fontSize: 18,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Replaces current records with a verified backup file.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const DialogSectionLabel('Backup archive'),
              if (file == null)
                Material(
                  color: p.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  child: InkWell(
                    key: const ValueKey('backup-pick-file'),
                    onTap: pickingFile ? null : onPickFile,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    hoverColor: p.selected.withValues(alpha: 0.45),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xl,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.medium),
                        border: Border.all(
                          color: p.accent.withValues(alpha: 0.5),
                          width: 1.25,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: p.cardBackground,
                              borderRadius: BorderRadius.circular(
                                AppRadii.medium,
                              ),
                              border: Border.all(color: p.border),
                            ),
                            child: Icon(
                              Icons.upload_file_outlined,
                              size: 22,
                              color: p.accentInk,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm + 2),
                          Text(
                            pickingFile
                                ? 'Opening file selector...'
                                : 'Select a backup file',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Select the backup file saved by this system',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Container(
                  key: const ValueKey('backup-selected-file'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.surfaceSunken,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    border: Border.all(color: p.accent.withValues(alpha: 0.55)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: p.selected,
                          borderRadius: BorderRadius.circular(AppRadii.small),
                        ),
                        child: Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: p.accentInk,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: p.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  _formatBytes(file.sizeBytes),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.textSecondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                StatusBadge(
                                  label: file.detectedExtension,
                                  tone: StatusTone.info,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove selected file',
                        onPressed: onClearFile,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              const DialogSectionLabel('Pre-restore safety checklist'),
              _SafetyCheckRow(
                key: const ValueKey('backup-check-recent'),
                value: confirmedRecentBackup,
                label:
                    'I have created or verified a recent backup of current data.',
                onChanged: onConfirmedRecentBackupChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              _SafetyCheckRow(
                key: const ValueKey('backup-check-shifts'),
                value: confirmedShiftsClosed,
                label:
                    'All active POS shifts are closed and staff are signed out.',
                onChanged: onConfirmedShiftsClosedChanged,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
          FilledButton.icon(
            key: const ValueKey('backup-restore-button'),
            onPressed: canRestore ? onRestorePressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.brandWhite,
              disabledBackgroundColor: p.surfaceSunken,
              disabledForegroundColor: p.textSecondary,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Restore backup'),
          ),
        ],
      ),
    );
  }
}

class _SchedulePolicyCard extends StatelessWidget {
  const _SchedulePolicyCard({
    required this.frequency,
    required this.retentionCount,
    this.serverConnected = false,
    required this.onFrequencyChanged,
    required this.onRetentionChanged,
  });

  final String frequency;
  final int retentionCount;
  final bool serverConnected;
  final ValueChanged<String> onFrequencyChanged;
  final ValueChanged<int> onRetentionChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded, size: 20, color: p.accentInk),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Automated schedule & retention',
                    style: AppTextStyles.h4.copyWith(
                      fontSize: 15.5,
                      color: p.textPrimary,
                    ),
                  ),
                ],
              ),
              StatusBadge(
                label: serverConnected
                    ? 'Synced with server'
                    : 'Pending server sync',
                tone: serverConnected ? StatusTone.success : StatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Define how often the server should take unattended backups and '
            'how many recent snapshots to keep on disk.',
            style: TextStyle(fontSize: 12.5, color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FREQUENCY',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in const [
                        'Daily',
                        'Weekly',
                        'Manual only',
                      ])
                        ChoiceChip(
                          label: Text(option),
                          selected: frequency == option,
                          backgroundColor: p.surfaceSunken,
                          selectedColor: p.selected,
                          checkmarkColor: p.accentInk,
                          side: BorderSide(
                            color: frequency == option ? p.accent : p.border,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: frequency == option
                                ? p.accentInk
                                : p.textPrimary,
                          ),
                          onSelected: (_) => onFrequencyChanged(option),
                        ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RETENTION WINDOW',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final count in const [7, 14, 30])
                        ChoiceChip(
                          label: Text('Keep last $count'),
                          selected: retentionCount == count,
                          backgroundColor: p.surfaceSunken,
                          selectedColor: p.selected,
                          checkmarkColor: p.accentInk,
                          side: BorderSide(
                            color: retentionCount == count
                                ? p.accent
                                : p.border,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: retentionCount == count
                                ? p.accentInk
                                : p.textPrimary,
                          ),
                          onSelected: (_) => onRetentionChanged(count),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScopeOptionTile extends StatelessWidget {
  const _ScopeOptionTile({
    required this.title,
    required this.subtitle,
    required this.checked,
    required this.onChanged,
    this.locked = false,
  });

  final String title;
  final String subtitle;
  final bool checked;
  final bool locked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return InkWell(
      onTap: locked || onChanged == null ? null : () => onChanged!(!checked),
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: checked ? p.selected.withValues(alpha: 0.45) : p.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(
            color: checked ? p.accent.withValues(alpha: 0.45) : p.border,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: locked || onChanged == null
                  ? null
                  : (v) => onChanged!(v ?? false),
              activeColor: p.accent,
              checkColor: p.onAccent,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                      if (locked) ...[
                        const SizedBox(width: 8),
                        StatusBadge(
                          label: checked ? 'Included' : 'Not included',
                          tone: StatusTone.info,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyCheckRow extends StatelessWidget {
  const _SafetyCheckRow({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: value ? p.accent : p.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: p.accent,
              checkColor: p.onAccent,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: p.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotCell extends StatelessWidget {
  const _SnapshotCell({required this.snapshot});

  final SystemBackupSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: p.selected,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(color: p.accent.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.archive_outlined, size: 18, color: p.accentInk),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                snapshot.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              if (snapshot.note.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  snapshot.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ManifestRow extends StatelessWidget {
  const _ManifestRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: p.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestoreConfirmDialog extends StatefulWidget {
  const _RestoreConfirmDialog({
    this.backupId,
    required this.filename,
    required this.sizeBytes,
    required this.format,
    required this.onConfirmRestore,
  });

  final String? backupId;
  final String filename;
  final int sizeBytes;
  final String format;
  final Future<void> Function() onConfirmRestore;

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  final TextEditingController _confirmController = TextEditingController();

  bool get _isConfirmed => _confirmController.text.trim() == 'RESTORE';

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final errorInk = p.isDark ? const Color(0xFFFCA5A5) : AppColors.errorText;
    final errorBg = p.isDark
        ? AppColors.error.withValues(alpha: 0.14)
        : AppColors.errorTint;

    return AppDialog(
      icon: Icons.warning_amber_rounded,
      title: 'Confirm system restore',
      subtitle: 'This operation replaces the current database state.',
      width: 480,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: errorBg,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              'Restoring ${widget.filename} (${_formatBytes(widget.sizeBytes)}, '
              '${widget.format}) will overwrite sales, inventory, and user '
              'records created after this snapshot. All cashiers must stop '
              'work until they sign in again; open sessions may still hold old '
              'access tokens.',
              style: TextStyle(fontSize: 13, height: 1.45, color: errorInk),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Type RESTORE to confirm you understand the impact:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const ValueKey('backup-restore-confirm-input'),
            controller: _confirmController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Type RESTORE'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('backup-restore-confirm-submit'),
          onPressed: !_isConfirmed
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onConfirmRestore();
                },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.brandWhite,
          ),
          child: const Text('Proceed with restore'),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}
