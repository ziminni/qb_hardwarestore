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
    required this.userName,
    required this.active,
  });

  final int id;
  final String phone;
  final String label;
  final String userName;
  final bool active;

  factory _SmsContact.fromJson(Map<String, dynamic> json) => _SmsContact(
    id: (json['id'] as num).toInt(),
    phone: (json['phone'] as String?) ?? '',
    label: (json['label'] as String?) ?? '',
    userName: (json['user_name'] as String?) ?? '',
    active: json['active'] == true,
  );
}

class _SmsStatus {
  const _SmsStatus({
    required this.enabled,
    required this.gatewayConfigured,
    required this.lastHeartbeat,
    required this.queued,
    required this.failed,
    required this.contacts,
  });

  final bool enabled;
  final bool gatewayConfigured;
  final DateTime? lastHeartbeat;
  final int queued;
  final int failed;
  final int contacts;

  factory _SmsStatus.fromJson(Map<String, dynamic> json) => _SmsStatus(
    enabled: json['enabled'] == true,
    gatewayConfigured: json['gateway_configured'] == true,
    lastHeartbeat: json['last_heartbeat'] is String
        ? DateTime.tryParse(json['last_heartbeat'] as String)?.toLocal()
        : null,
    queued: (json['queued'] as num?)?.toInt() ?? 0,
    failed: (json['failed'] as num?)?.toInt() ?? 0,
    contacts: (json['contacts'] as num?)?.toInt() ?? 0,
  );
}

/// Shared Settings panel for System Administrators and Store Managers to
/// register authorized Bodega Checker phone numbers and inspect the USB SMS
/// modem gateway status (`/api/v1/sms/contacts/` & `/api/v1/sms/status/`).
class SmsContactsSettingsPanel extends StatefulWidget {
  const SmsContactsSettingsPanel({super.key});

  @override
  State<SmsContactsSettingsPanel> createState() =>
      _SmsContactsSettingsPanelState();
}

class _SmsContactsSettingsPanelState extends State<SmsContactsSettingsPanel> {
  final _phoneCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  _SmsStatus? _status;
  List<_SmsContact> _contacts = const [];

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
      ]);
      final statusRaw = results[0].data;
      final contactsRaw = results[1].data;
      final list = contactsRaw is List
          ? contactsRaw
          : (contactsRaw is Map && contactsRaw['results'] is List
                ? contactsRaw['results'] as List
                : const []);
      if (!mounted) return;
      setState(() {
        _status = statusRaw is Map<String, dynamic>
            ? _SmsStatus.fromJson(statusRaw)
            : null;
        _contacts = [
          for (final row in list)
            if (row is Map<String, dynamic>) _SmsContact.fromJson(row),
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
        data: {'phone': phone, 'label': label, 'active': true},
      );
      _phoneCtrl.clear();
      _labelCtrl.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS contact added.')),
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

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final status = _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!, onRetry: _load),
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
                    Text(
                      'Queued: ${status?.queued ?? 0} · Failed: ${status?.failed ?? 0}',
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
                'Phones registered here receive pickup alerts from the store SIM800C modem '
                'and can confirm Bodega releases offline via SMS.',
                style: TextStyle(fontSize: 13, color: p.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
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
                    child: TextField(
                      key: const ValueKey('sms-contact-label-field'),
                      controller: _labelCtrl,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Label (optional)',
                        hintText: 'e.g. Bodega Checker Phone',
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
                                  if (_contacts[i].label.isNotEmpty ||
                                      _contacts[i].userName.isNotEmpty)
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
      ],
    );
  }
}
