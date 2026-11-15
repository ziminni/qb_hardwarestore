import 'package:client/data/models/product_image_upload.dart';
import 'package:file_selector/file_selector.dart';

/// A pick that could not become an upload, with a message safe to show.
class ImageFileException implements Exception {
  const ImageFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Opens the OS file dialog. Injectable so tests need no real dialog.
typedef PickImageFile = Future<XFile?> Function();

/// Turns the picked handle into bytes. Injectable for the same reason.
typedef ReadPickedImage = Future<ProductImageUpload> Function(XFile file);

/// The product photo picker: hands the form BYTES, never a device path.
///
/// It used to return `XFile.path`, which the draft then posted as `image_url` —
/// a field the server validates as a URL, so every photo was refused and the
/// preview worked only until the form was saved. Reading the bytes here also
/// makes the pick work where a path is worthless (web, and the Windows
/// `file://`-style handles), and lets the 5 MiB cap be checked before anything
/// is uploaded.
class ImageFileService {
  const ImageFileService({PickImageFile? pickFile, ReadPickedImage? onRead})
    : _pickFile = pickFile,
      _onRead = onRead;

  final PickImageFile? _pickFile;
  final ReadPickedImage? _onRead;

  static const _tooLarge =
      'That image is larger than 5 MB. Choose a smaller photo.';
  static const _unreadable =
      'That image could not be read. Copy it somewhere else and try again.';

  static const _imageTypes = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png', 'webp'],
    uniformTypeIdentifiers: [
      'public.jpeg',
      'public.png',
      'org.webmproject.webp',
    ],
  );

  /// The picked photo, or null when the clerk cancelled.
  ///
  /// Throws [ImageFileException] when the file is too big or cannot be read, so
  /// the form can say WHY nothing was picked instead of failing silently.
  Future<ProductImageUpload?> selectImage() async {
    final file = await (_pickFile ?? _openDialog)();
    if (file == null) return null;
    if (_onRead case final read?) return read(file);
    try {
      // Size first: a file over the cap must not be read into memory at all.
      if (await file.length() > ProductImageUpload.maxBytes) {
        throw const ImageFileException(_tooLarge);
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > ProductImageUpload.maxBytes) {
        throw const ImageFileException(_tooLarge);
      }
      return ProductImageUpload(bytes: bytes, filename: _nameOf(file));
    } on ImageFileException {
      rethrow;
    } catch (_) {
      // A moved, locked or unreadable file throws a platform exception whose
      // text names a path — useless to a clerk.
      throw const ImageFileException(_unreadable);
    }
  }

  static Future<XFile?> _openDialog() =>
      openFile(acceptedTypeGroups: const [_imageTypes]);

  /// The file's own name, never its directory.
  static String _nameOf(XFile file) {
    final name = file.name;
    if (name.isNotEmpty) return name;
    return file.path.split(RegExp(r'[/\\]')).last;
  }
}
