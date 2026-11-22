import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/network/api_client.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class _SmsContact {
  const _SmsContact({
    required this.id,
    required this.phone,
    required this.label,
    required this.userId,
    required this.userName,
    required this.active,
  });

  final int id;
  final String phone;
  final String label;
  final int? userId;
  final String userName;
  final bool active;

  factory _SmsContact.fromJson(Map<String, dynamic> json) => _SmsContact(
    id: (json['id'] as num).toInt(),
    phone: (json['phone'] as String?) ?? '',
    label: (json['label'] as String?) ?? '',
    userId: (json['user'] as num?)?.toInt(),
    userName: (json['user_name'] as String?) ?? '',
    active: json['active'] == true,
  );
}

class _SmsUserOption {
  const _SmsUserOption({
    required this.id,
    required this.displayName,
    required this.roleSummary,
    required this.isBodegaPrimary,
  });

  final int id;
  final String displayName;
  final String roleSummary;
  final bool isBodegaPrimary;
}

class _SmsMessageRow {
  const _SmsMessageRow({
    required this.id,
    required this.direction,
    required this.phone,
    required this.body,
    required this.status,
    required this.result,
    required this.lastError,
    required this.createdAt,
  });

  final int id;
  final String direction;
  final String phone;
  final String body;
  final String status;
  final String result;
  final String lastError;
  final DateTime? createdAt;

  factory _SmsMessageRow.fromJson(Map<String, dynamic> json) => _SmsMessageRow(
    id: (json['id'] as num).toInt(),
    direction: (json['direction'] as String?) ?? '',
    phone: (json['phone'] as String?) ?? '',
    body: (json['body'] as String?) ?? '',
    status: (json['status'] as String?) ?? '',
    result: (json['result'] as String?) ?? '',
    lastError: (json['last_error'] as String?) ?? '',
    createdAt: json['created_at'] is String
        ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
        : null,
  );
}

class _SmsStatus {
  const _SmsStatus({
    required this.enabled,
    required this.gatewayConfigured,
    required this.lastHeartbeat,
    required this.operatorName,
    required this.signal,
    required this.queued,
    required this.failed,
    required this.contacts,
  });

  final bool enabled;
  final bool gatewayConfigured;
  final DateTime? lastHeartbeat;
  final String operatorName;
  final int signal;
  final int queued;
  final int failed;
  final int contacts;

  factory _SmsStatus.fromJson(Map<String, dynamic> json) {
    final info = json['heartbeat_info'] is Map
        ? json['heartbeat_info'] as Map
        : const <String, dynamic>{};
    return _SmsStatus(
      enabled: json['enabled'] == true,
      gatewayConfigured: json['gateway_configured'] == true,
      lastHeartbeat: json['last_heartbeat'] is String
          ? DateTime.tryParse(json['last_heartbeat'] as String)?.toLocal()
          : null,
      operatorName: (info['operator'] as String?) ?? '',
      signal: (info['signal'] as num?)?.toInt() ?? 0,
      queued: (json['queued'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      contacts: (json['contacts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Shared Settings panel for System Administrators and Store Managers to
/// register authorized Bodega Checker phone numbers, link each number to a
/// Bodega-capable account, inspect USB SMS modem status, and review the SMS log.
class SmsContactsSettingsPanel extends StatefulWidget {
  const SmsContactsSettingsPanel({super.key});

  @override
  State<SmsContactsSettingsPanel> createState() =>
      _SmsContactsSettingsPanelState();
}

class _SmsContactsSettingsPanelState extends State<SmsContactsSettingsPanel> {
  static const _bodegaRoleCodes = {'bodega', 'inventory', 'sales', 'admin'};

  final _phoneCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  _SmsStatus? _status;
  List<_SmsContact> _contacts = const [];
  List<_SmsUserOption> _users = const [];
  List<_SmsMessageRow> _messages = const [];
  int? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  String _dioError(Object err) {
    if (err is DioException) {
      final data = err.response?.data;
      if (data is Map) {
        for (final entry in data.entries) {
          final val = entry.value;
          if (val is List && val.isNotEmpty) return '${val.first}';
          if (val is String && val.isNotEmpty) return val;
        }
      }
      return err.message ?? 'Could not reach the POS server.';
    }
    return '$err';
  }

  List<dynamic> _unwrapList(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map && raw['results'] is List) {
      return raw['results'] as List<dynamic>;
    }
    return const [];
  }

  List<_SmsUserOption> _parseEligibleUsers(dynamic raw) {
    final options = <_SmsUserOption>[];
    for (final row in _unwrapList(raw)) {
      if (row is! Map<String, dynamic>) continue;
      if (row['is_active'] != true) continue;
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;

      final roleCodes = <String>[];
      final roleLabels = <String>[];
      final rolesRaw = row['roles'];
      if (rolesRaw is List) {
        for (final r in rolesRaw) {
          if (r is Map) {
            final code = (r['name'] as String?)?.toLowerCase() ?? '';
            final disp = (r['display_name'] as String?) ?? code;
            if (code.isNotEmpty) roleCodes.add(code);
            if (disp.isNotEmpty) roleLabels.add(disp);
          }
        }
      }
      if (roleCodes.isEmpty && row['role'] is Map) {
        final r = row['role'] as Map;
        final code = (r['name'] as String?)?.toLowerCase() ?? '';
        final disp = (r['display_name'] as String?) ?? code;
        if (code.isNotEmpty) roleCodes.add(code);
        if (disp.isNotEmpty) roleLabels.add(disp);
      }

      if (!roleCodes.any(_bodegaRoleCodes.contains)) continue;
      final fullName = (row['full_name'] as String?)?.trim() ?? '';
      final username = (row['username'] as String?)?.trim() ?? '';
      options.add(
        _SmsUserOption(
          id: id,
          displayName: fullName.isNotEmpty ? fullName : username,
          roleSummary: roleLabels.join(', '),
          isBodegaPrimary: roleCodes.contains('bodega'),
        ),
      );
    }
    options.sort((a, b) {
      if (a.isBodegaPrimary != b.isBodegaPrimary) {
        return a.isBodegaPrimary ? -1 : 1;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return options;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ApiClient.instance.dio;
      final results = await Future.wait([
        dio.get<dynamic>('/api/v1/sms/status/'),
        dio.get<dynamic>('/api/v1/sms/contacts/'),
        dio.get<dynamic>('/api/v1/users/').catchError(
          (_) => Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/v1/users/'),
            data: const <dynamic>[],
          ),
        ),
        dio.get<dynamic>('/api/v1/sms/messages/').catchError(
          (_) => Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/v1/sms/messages/'),
            data: const <dynamic>[],
          ),
        ),
      ]);
      final statusRaw = results[0].data;
      final contactsList = _unwrapList(results[1].data);
      final usersList = _parseEligibleUsers(results[2].data);
      final messagesList = _unwrapList(results[3].data);
      if (!mounted) return;
      setState(() {
        _status = statusRaw is Map<String, dynamic>
            ? _SmsStatus.fromJson(statusRaw)
            : null;
        _contacts = [
          for (final row in contactsList)
            if (row is Map<String, dynamic>) _SmsContact.fromJson(row),
        ];
        _users = usersList;
        if (_selectedUserId == null ||
            !_users.any((u) => u.id == _selectedUserId)) {
          _selectedUserId = _users.firstOrNull?.id;
        }
        _messages = [
          for (final row in messagesList.take(10))
            if (row is Map<String, dynamic>) _SmsMessageRow.fromJson(row),
        ];
      });
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _error = _dioError(err));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addContact() async {
    final phone = _phoneCtrl.text.trim();
    final label = _labelCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter a mobile number (e.g. 09171234567).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post<dynamic>(
        '/api/v1/sms/contacts/',
        data: {
          'phone': phone,
          'label': label,
          'active': true,
          if (_selectedUserId != null) 'user': _selectedUserId,
        },
      );
      _phoneCtrl.clear();
      _labelCtrl.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS contact added and linked.')),
        );
      }
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _error = _dioError(err));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _linkContactUser(_SmsContact contact, int userId) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.patch<dynamic>(
        '/api/v1/sms/contacts/${contact.id}/',
        data: {'user': userId},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Linked ${contact.phone} to account.')),
        );
      }
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _error = _dioError(err));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive(_SmsContact contact, bool next) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.patch<dynamic>(
        '/api/v1/sms/contacts/${contact.id}/',
        data: {'active': next},
      );
      await _load();
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _error = _dioError(err));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteContact(_SmsContact contact) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.delete<dynamic>(
        '/api/v1/sms/contacts/${contact.id}/',
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${contact.phone}.')),
        );
      }
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _error = _dioError(err));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _retryMessage(int messageId) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post<dynamic>(
        '/api/v1/sms/messages/$messageId/retry/',
      );
      await _load();
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _error = _dioError(err));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final status = _status;
    final linkedActiveCount = _contacts
        .where((c) => c.active && c.userId != null)
        .length;
    final unlinkedCount = _contacts
        .where((c) => c.active && c.userId == null)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!, onRetry: _load),
          const SizedBox(height: AppSpacing.md),
        ],
        if (unlinkedCount > 0) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.warningTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warningText.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: AppColors.warningText,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '$unlinkedCount registered SMS ${unlinkedCount == 1 ? 'number is' : 'numbers are'} '
                    'not linked to a Bodega account yet. Link an account below so POS pickup '
                    'alerts can be sent and DONE replies are accepted.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warningText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        AppPanel(
          title: 'USB SMS Gateway Status',
          trailing: TextButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Refresh'),
          ),
          child: _loading && status == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: CircularProgressIndicator(),
                  ),
                )
              : Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(
                      label: (status?.enabled ?? false)
                          ? 'SMS Enabled'
                          : 'SMS Disabled',
                      tone: (status?.enabled ?? false)
                          ? StatusTone.success
                          : StatusTone.neutral,
                    ),
                    StatusBadge(
                      label: status?.lastHeartbeat != null
                          ? 'Modem seen ${formatDateTime(status!.lastHeartbeat!)}'
                          : 'Waiting for bridge heartbeat',
                      tone: status?.lastHeartbeat != null
                          ? StatusTone.success
                          : StatusTone.warning,
                    ),
                    if (status != null && status.operatorName.isNotEmpty)
                      Text(
                        '${status.operatorName} · Signal ${status.signal}/31',
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                    Text(
                      'Ready phones: $linkedActiveCount · Queued: ${status?.queued ?? 0} · Failed: ${status?.failed ?? 0}',
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPanel(
          title: 'Add Authorized Bodega Phone',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Phones registered and linked to a Bodega-capable account receive pickup alerts '
                'from the store SIM800C modem and can confirm Bodega releases offline via SMS.',
                style: TextStyle(fontSize: 13, color: p.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      key: const ValueKey('sms-contact-phone-field'),
                      controller: _phoneCtrl,
                      enabled: !_saving,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        hintText: '09171234567 or +63917...',
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('sms-contact-user-$_selectedUserId-${_users.length}'),
                      isExpanded: true,
                      initialValue: _selectedUserId,
                      decoration: const InputDecoration(
                        labelText: 'Linked Bodega account',
                        isDense: true,
                      ),
                      items: [
                        for (final u in _users)
                          DropdownMenuItem(
                            value: u.id,
                            child: Text(
                              '${u.displayName} (${u.roleSummary})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _selectedUserId = v),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      key: const ValueKey('sms-contact-label-field'),
                      controller: _labelCtrl,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Label (optional)',
                        hintText: 'e.g. Bodega Phone 1',
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      key: const ValueKey('sms-contact-add-button'),
                      onPressed: _saving ? null : _addContact,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add number'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPanel(
          title: 'Registered SMS Numbers (${_contacts.length})',
          child: _contacts.isEmpty
              ? Text(
                  'No authorized phone numbers yet. Add a Bodega Checker number above.',
                  style: TextStyle(fontSize: 13, color: p.textSecondary),
                )
              : Column(
                  children: [
                    for (var i = 0; i < _contacts.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.sms_outlined,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _contacts[i].phone,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_contacts[i].userId == null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          const StatusBadge(
                                            label: 'Unlinked — SMS inactive',
                                            tone: StatusTone.warning,
                                          ),
                                          if (_users.isNotEmpty)
                                            SizedBox(
                                              width: 220,
                                              child: DropdownButtonFormField<int>(
                                                isExpanded: true,
                                                decoration: const InputDecoration(
                                                  labelText: 'Link account…',
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                ),
                                                items: [
                                                  for (final u in _users)
                                                    DropdownMenuItem(
                                                      value: u.id,
                                                      child: Text(
                                                        u.displayName,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                ],
                                                onChanged: _saving
                                                    ? null
                                                    : (uid) {
                                                        if (uid != null) {
                                                          _linkContactUser(
                                                            _contacts[i],
                                                            uid,
                                                          );
                                                        }
                                                      },
                                              ),
                                            ),
                                        ],
                                      ),
                                    )
                                  else
                                    Text(
                                      [
                                        if (_contacts[i].label.isNotEmpty)
                                          _contacts[i].label,
                                        if (_contacts[i].userName.isNotEmpty)
                                          'Account: ${_contacts[i].userName}',
                                      ].join(' · '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: p.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _contacts[i].active,
                              onChanged: _saving
                                  ? null
                                  : (v) => _toggleActive(_contacts[i], v),
                            ),
                            IconButton(
                              tooltip: 'Remove number',
                              onPressed: _saving
                                  ? null
                                  : () => _deleteContact(_contacts[i]),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: AppColors.errorText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPanel(
          title: 'Recent SMS Activity (${_messages.length})',
          child: _messages.isEmpty
              ? Text(
                  'No SMS messages yet. Sell a product stored in Bodega to trigger an outbound pickup SMS.',
                  style: TextStyle(fontSize: 13, color: p.textSecondary),
                )
              : Column(
                  children: [
                    for (var i = 0; i < _messages.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StatusBadge(
                              label: _messages[i].direction == 'OUT'
                                  ? 'OUT'
                                  : 'IN',
                              tone: _messages[i].direction == 'OUT'
                                  ? StatusTone.info
                                  : StatusTone.neutral,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_messages[i].phone} · ${_messages[i].status}'
                                    '${_messages[i].createdAt != null ? ' · ${formatDateTime(_messages[i].createdAt!)}' : ''}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _messages[i].body,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (_messages[i].result.isNotEmpty)
                                    Text(
                                      'Reply: ${_messages[i].result}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: p.textSecondary,
                                      ),
                                    ),
                                  if (_messages[i].lastError.isNotEmpty)
                                    Text(
                                      'Error: ${_messages[i].lastError}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.errorText,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (_messages[i].direction == 'OUT' &&
                                _messages[i].status == 'FAILED')
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => _retryMessage(_messages[i].id),
                                child: const Text('Retry'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
