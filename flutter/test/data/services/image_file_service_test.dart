// Product image lane: the picker must hand the form BYTES, never a device path.
//
// The root bug was `ImageFileService.selectImage()` returning `C:\...\photo.png`,
// which the draft then posted as `image_url`. These tests pin the replacement:
// bytes plus a file name, a 5 MiB cap checked before anything is uploaded, and
// the two ways a pick fails (cancel, unreadable file) said plainly.

import 'dart:typed_data';

import 'package:client/data/models/product_image_upload.dart';
import 'package:client/data/services/image_file_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

/// A picker that answers with a file built from data, so no real disk or OS
/// dialog is involved.
ImageFileService _serviceFor(XFile? file) =>
    ImageFileService(pickFile: () async => file);

void main() {
  test('returns the picked file as bytes and a file name', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final service = _serviceFor(
      XFile.fromData(bytes, path: '/somewhere/photo.png'),
    );

    final picked = await service.selectImage();

    expect(picked, isNotNull);
    expect(picked!.bytes, bytes);
    expect(picked.filename, 'photo.png');
  });

  test('a cancelled pick answers null, so the form keeps what it had', () async {
    expect(await _serviceFor(null).selectImage(), isNull);
  });

  test('an oversized image is refused before it is read', () async {
    // `length` is overridden so the cap is exercised without a 6 MB allocation.
    final service = _serviceFor(
      XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        path: '/somewhere/huge.png',
        length: ProductImageUpload.maxBytes + 1,
      ),
    );

    await expectLater(
      service.selectImage(),
      throwsA(
        isA<ImageFileException>().having(
          (e) => e.message,
          'message',
          contains('5 MB'),
        ),
      ),
    );
  });

  test('an unreadable file is reported, not thrown raw', () async {
    final service = _serviceFor(
      XFile('/definitely/not/here/photo.png'),
    );

    await expectLater(
      service.selectImage(),
      throwsA(
        isA<ImageFileException>().having(
          (e) => e.message,
          'message',
          contains('could not be read'),
        ),
      ),
    );
  });

  test('the cap is 5 MiB', () {
    expect(ProductImageUpload.maxBytes, 5 * 1024 * 1024);
  });
}
