import 'dart:typed_data';

/// A photo the clerk picked, held in memory until the product is saved.
///
/// It exists because the two things a device file gives you are exactly the two
/// things that must never travel to the server: its PATH (a `C:\...` or a
/// `file://` URL is meaningless there) and its platform handle. The bytes and a
/// harmless name are what `POST/PATCH /api/v1/products/` accepts as the
/// `multipart/form-data` field `image`.
class ProductImageUpload {
  const ProductImageUpload({required this.bytes, required this.filename});

  /// The server's limit (`PRODUCT_IMAGE_TOO_LARGE` past it). Checked before the
  /// read, so a 40 MB photo is refused on this machine instead of after a slow
  /// upload.
  static const maxBytes = 5 * 1024 * 1024;

  final Uint8List bytes;

  /// The file's own name, for the label and the multipart part — never a path.
  final String filename;
}
