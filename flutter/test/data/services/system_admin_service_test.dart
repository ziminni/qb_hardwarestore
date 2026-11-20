// Restore/download wire tests for the Admin Backup & Restore workspace.
//
// Why here and not through a stubbed page service: the original bug was a LOCAL
// file restore sending only its file name, so the server could restore a
// different same-name snapshot (or answer 404) while the UI showed success. Only
// the real `SystemAdminService` -> `ApiClient` stack shows what actually travels,
// so these tests drive it against a fake adapter and assert the body bytes.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/system_admin_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every request and answers from [respond].
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.respond);

  final (int, Object) Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = respond(options);
    if (body is List<int>) {
      return ResponseBody.fromBytes(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['application/octet-stream'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _restorePath = '/api/v1/system/backups/restore/';

const _restored = {
  'restored': true,
  'source': 'uploaded file backup.json',
  'records': 42,
  'safety_backup_id': 'bk-safety-1',
  'restored_at': '2026-11-19T22:00:00+08:00',
};

final _fileBytes = Uint8List.fromList(utf8.encode('[{"model":"auth.user"}]'));

MapEntry<String, MultipartFile>? _filePart(Object? payload) {
  if (payload is! FormData) return null;
  for (final file in payload.files) {
    if (file.key == 'file') return file;
  }
  return null;
}

void main() {
  late ApiClient client;
  setUpAll(() => client = ApiClient.instance..init());

  late _RecordingAdapter adapter;
  const service = SystemAdminService();

  void answer((int, Object) Function(RequestOptions options) respond) {
    adapter = _RecordingAdapter(respond);
    client.dio.httpClientAdapter = adapter;
  }

  test(
    'local restore uploads the picked file bytes, never the name alone',
    () async {
      answer((_) => (200, _restored));

      await service.restoreBackup(filename: 'backup.json', bytes: _fileBytes);

      final payload = adapter.requests.single.data;
      expect(adapter.requests.single.path, _restorePath);
      expect(payload, isA<FormData>(), reason: 'bytes force multipart upload');
      expect(payload, isNot({'filename': 'backup.json'}));
      final part = _filePart(payload);
      expect(part, isNotNull, reason: 'the file must travel as a `file` part');
      expect(part!.value.filename, 'backup.json');
      expect(part.value.length, _fileBytes.length);
    },
  );

  test('server snapshot restore sends backup_id JSON only', () async {
    answer((_) => (200, _restored));

    await service.restoreBackup(backupId: 'bk-1');

    expect(adapter.requests.single.data, {'backup_id': 'bk-1'});
  });

  test('restore with neither bytes nor backup_id is refused locally', () async {
    answer((_) => (200, _restored));

    await expectLater(
      service.restoreBackup(filename: 'backup.json'),
      throwsA(isA<SystemAdminServiceException>()),
    );
    expect(
      adapter.requests,
      isEmpty,
      reason: 'no name-only request on the wire',
    );
  });

  test('a response without restored:true is an error, not success', () async {
    answer((_) => (200, const <String, dynamic>{}));

    await expectLater(
      service.restoreBackup(backupId: 'bk-1'),
      throwsA(isA<SystemAdminServiceException>()),
    );
  });

  test('a restored:false response is an error', () async {
    answer((_) => (200, {'restored': false}));

    await expectLater(
      service.restoreBackup(backupId: 'bk-1'),
      throwsA(isA<SystemAdminServiceException>()),
    );
  });

  test('server refusal detail reaches the admin', () async {
    answer(
      (_) => (
        404,
        {
          'code': 'BACKUP_NOT_FOUND',
          'detail': 'This server has no such backup.',
        },
      ),
    );

    await expectLater(
      service.restoreBackup(backupId: 'bk-missing'),
      throwsA(
        isA<SystemAdminServiceException>().having(
          (e) => e.message,
          'message',
          contains('no such backup'),
        ),
      ),
    );
  });

  test('download asks for bytes and returns them unparsed', () async {
    answer((_) => (200, _fileBytes));

    final result = await service.downloadBackup('bk-1');

    expect(result, _fileBytes);
    final request = adapter.requests.single;
    expect(request.path, '/api/v1/system/backups/bk-1/download/');
    expect(request.responseType, ResponseType.bytes);
  });

  test('download of an empty file is refused', () async {
    answer((_) => (200, <int>[]));

    await expectLater(
      service.downloadBackup('bk-1'),
      throwsA(isA<SystemAdminServiceException>()),
    );
  });
}
