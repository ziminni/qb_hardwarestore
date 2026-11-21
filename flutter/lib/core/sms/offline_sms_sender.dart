import 'package:client/core/config/api_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Outcome of attempting an offline Bodega SMS release reply.
enum OfflineSmsOutcome { sent, composer, skipped, failed }

/// Sends `DONE <reference> <4-digit-code> [receiver]` to the store's GSM modem
/// when the Bodega Android phone is offline.
///
/// Option B first (direct Android `SmsManager`), automatically falling back to
/// Option A (pre-filled Android Messages composer) if permission is denied or
/// direct send fails. Safe no-op on desktop/web/tests.
class OfflineSmsSender {
  OfflineSmsSender._();

  static const _channel = MethodChannel('buildpro/sms');

  static String buildReleaseBody({
    required String reference,
    required String smsCode,
    String receivedBy = '',
  }) {
    final parts = <String>[
      'DONE',
      reference.trim(),
      smsCode.trim(),
      if (receivedBy.trim().isNotEmpty) receivedBy.trim(),
    ];
    return parts.join(' ');
  }

  static Future<OfflineSmsOutcome> sendReleaseReply({
    required String reference,
    required String smsCode,
    String receivedBy = '',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return OfflineSmsOutcome.skipped;
    }
    final phone = ApiConfig.storeSmsNumber.trim();
    if (phone.isEmpty || reference.trim().isEmpty || smsCode.trim().isEmpty) {
      return OfflineSmsOutcome.skipped;
    }
    final body = buildReleaseBody(
      reference: reference,
      smsCode: smsCode,
      receivedBy: receivedBy,
    );
    try {
      final res = await _channel.invokeMethod<String>('sendSms', {
        'phone': phone,
        'body': body,
      });
      return switch (res) {
        'sent' => OfflineSmsOutcome.sent,
        'composer' => OfflineSmsOutcome.composer,
        'skipped' => OfflineSmsOutcome.skipped,
        _ => OfflineSmsOutcome.failed,
      };
    } on Object {
      return OfflineSmsOutcome.failed;
    }
  }
}
