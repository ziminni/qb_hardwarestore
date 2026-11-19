import 'package:client/core/network/api_client.dart';
import 'package:client/features/admin/views/admin_backup_restore_page.dart';
import 'package:client/features/admin/views/admin_security_page.dart';
import 'package:dio/dio.dart';

class SystemAdminServiceException implements Exception {
  const SystemAdminServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SecurityPolicyState {
  const SecurityPolicyState({
    this.minPasswordLength = 8,
    this.idleTimeout = '30 min',
    this.lockoutThreshold = 5,
    this.requireManagerOverride = true,
  });

  final int minPasswordLength;
  final String idleTimeout;
  final int lockoutThreshold;
  final bool requireManagerOverride;

  factory SecurityPolicyState.fromJson(Map<String, dynamic> json) =>
      SecurityPolicyState(
        minPasswordLength: (json['min_password_length'] as num?)?.toInt() ?? 8,
        idleTimeout: (json['idle_timeout'] as String?) ?? '30 min',
        lockoutThreshold: (json['lockout_threshold'] as num?)?.toInt() ?? 5,
        requireManagerOverride:
            (json['require_manager_override'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
    'min_password_length': minPasswordLength,
    'idle_timeout': idleTimeout,
    'lockout_threshold': lockoutThreshold,
    'require_manager_override': requireManagerOverride,
  };
}

class SecurityOverviewPayload {
  const SecurityOverviewPayload({
    required this.policy,
    required this.sessions,
    required this.loginEvents,
  });

  final SecurityPolicyState policy;
  final List<ActiveSessionRecord> sessions;
  final List<LoginActivityRecord> loginEvents;
}

class BackupScheduleState {
  const BackupScheduleState({
    this.frequency = 'Daily',
    this.retentionCount = 14,
  });

  final String frequency;
  final int retentionCount;

  factory BackupScheduleState.fromJson(Map<String, dynamic> json) =>
      BackupScheduleState(
        frequency: (json['frequency'] as String?) ?? 'Daily',
        retentionCount: (json['retention_count'] as num?)?.toInt() ?? 14,
      );
}

class BackupManifestPayload {
  const BackupManifestPayload({
    required this.schedule,
    required this.snapshots,
  });

  final BackupScheduleState schedule;
  final List<SystemBackupSnapshot> snapshots;
}

/// Service connecting Admin Security (`/admin/security`) and Admin Backup &
/// Restore (`/admin/backup-restore`) to `/api/v1/system/...` on the Django
/// backend.
class SystemAdminService {
  const SystemAdminService();

  static ActiveSessionRecord parseSession(Map<String, dynamic> json) {
    final rawDate = (json['last_seen_at'] as String?) ?? '';
    return ActiveSessionRecord(
      id: '${json['id'] ?? ''}',
      fullName: (json['full_name'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      roleLabel: (json['role_label'] as String?) ?? 'Staff',
      deviceLabel: (json['device_label'] as String?) ?? 'POS terminal',
      ipAddress: (json['ip_address'] as String?) ?? '127.0.0.1',
      lastSeenAt: DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now(),
      isCurrentDevice: (json['is_current_device'] as bool?) ?? false,
    );
  }

  static LoginActivityRecord parseLoginEvent(Map<String, dynamic> json) {
    final rawDate = (json['timestamp'] as String?) ?? '';
    return LoginActivityRecord(
      id: '${json['id'] ?? ''}',
      username: (json['username'] as String?) ?? 'unknown',
      deviceLabel: (json['device_label'] as String?) ?? 'POS client',
      ipAddress: (json['ip_address'] as String?) ?? '127.0.0.1',
      timestamp: DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now(),
      succeeded: (json['succeeded'] as bool?) ?? true,
      note: (json['note'] as String?) ?? '',
    );
  }

  static SystemBackupSnapshot parseSnapshot(Map<String, dynamic> json) {
    final rawDate = (json['created_at'] as String?) ?? '';
    final originRaw = (json['origin'] as String?) ?? 'Manual';
    return SystemBackupSnapshot(
      id: '${json['id'] ?? ''}',
      filename: (json['filename'] as String?) ?? '',
      createdAt: DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      format: (json['format'] as String?) ?? '.dump',
      origin: originRaw == 'Scheduled'
          ? BackupOrigin.scheduled
          : BackupOrigin.manual,
      createdBy: (json['created_by'] as String?) ?? 'Administrator',
      includesMedia: (json['includes_media'] as bool?) ?? false,
      note: (json['note'] as String?) ?? '',
    );
  }

  static String _readError(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
    return fallback;
  }

  Future<SecurityOverviewPayload> fetchSecurityOverview() async {
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/v1/system/security/',
      );
      final data = response.data ?? const <String, dynamic>{};
      final policyJson =
          (data['policy'] as Map<String, dynamic>?) ?? const {};
      final sessionsList = (data['sessions'] as List?) ?? const [];
      final eventsList = (data['login_events'] as List?) ?? const [];

      return SecurityOverviewPayload(
        policy: SecurityPolicyState.fromJson(policyJson),
        sessions: [
          for (final item in sessionsList)
            if (item is Map<String, dynamic>) parseSession(item),
        ],
        loginEvents: [
          for (final item in eventsList)
            if (item is Map<String, dynamic>) parseLoginEvent(item),
        ],
      );
    } on DioException catch (e) {
      throw SystemAdminServiceException(
        _readError(e, 'Could not load security overview.'),
      );
    } catch (e) {
      throw SystemAdminServiceException('$e');
    }
  }

  Future<SecurityPolicyState> updateSecurityPolicy(
    SecurityPolicyState policy,
  ) async {
    try {
      final response = await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/v1/system/security/policy/',
        data: policy.toJson(),
      );
      return SecurityPolicyState.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw SystemAdminServiceException(
        _readError(e, 'Could not update security policy.'),
      );
    } catch (e) {
      throw SystemAdminServiceException('$e');
    }
  }

  Future<void> revokeSession(String sessionId) async {
    try {
      await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/v1/system/security/sessions/$sessionId/revoke/',
      );
    } on DioException catch (e) {
      throw SystemAdminServiceException(
        _readError(e, 'Could not revoke the session.'),
      );
    } catch (e) {
      throw SystemAdminServiceException('$e');
    }
  }

  Future<BackupManifestPayload> fetchBackups() async {
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/v1/system/backups/',
      );
      final data = response.data ?? const <String, dynamic>{};
      final scheduleJson =
          (data['schedule'] as Map<String, dynamic>?) ?? const {};
      final snapshotsList = (data['snapshots'] as List?) ?? const [];
      return BackupManifestPayload(
        schedule: BackupScheduleState.fromJson(scheduleJson),
        snapshots: [
          for (final item in snapshotsList)
            if (item is Map<String, dynamic>) parseSnapshot(item),
        ],
      );
    } on DioException catch (e) {
      throw SystemAdminServiceException(
        _readError(e, 'Could not load server backups.'),
      );
    } catch (e) {
      throw SystemAdminServiceException('$e');
    }
  }

  Future<SystemBackupSnapshot> createBackup({
    required String format,
    required bool includeMedia,
    required bool includeAuditLogs,
    String note = '',
  }) async {
    try {
      final response = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/v1/system/backups/',
        data: {
          'format': format,
          'include_media': includeMedia,
          'include_audit_logs': includeAuditLogs,
          'note': note,
          'origin': 'Manual',
        },
      );
      return parseSnapshot(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw SystemAdminServiceException(
        _readError(e, 'Could not create database backup.'),
      );
    } catch (e) {
      throw SystemAdminServiceException('$e');
    }
  }

  Future<BackupScheduleState> updateBackupSchedule({
    required String frequency,
    required int retentionCount,
  }) async {
    try {
      final response = await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/v1/system/backups/schedule/',
        data: {
          'frequency': frequency,
          'retention_count': retentionCount,
        },
      );
      return BackupScheduleState.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw SystemAdminServiceException(
        _readError(e, 'Could not update backup schedule.'),
      );
    } catch (e) {
      throw SystemAdminServiceException('$e');
    }
  }

  Future<void> restoreBackup({
    String? backupId,
    String? filename,
  }) async {
    try {
      await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/v1/system/backups/restore/',
        data: {
          if (backupId != null && backupId.isNotEmpty) 'backup_id': backupId,
          if (filename != null && filename.isNotEmpty) 'filename': filename,
        },
      );
    } on DioException catch (e) {
      throw SystemAdminServiceException(
        _readError(e, 'Could not restore database snapshot.'),
      );
    } catch (e) {
      throw SystemAdminServiceException('$e');
    }
  }
}
