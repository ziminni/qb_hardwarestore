import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProductsImage extends StatelessWidget {
  const ProductsImage({
    super.key,
    this.imageUrl = '',
    this.imageBytes,
    this.width = 48,
    this.height = 48,
    this.fit = BoxFit.cover,
  });

  /// The server's `image_url`, or a legacy device path.
  final String imageUrl;

  /// A photo the clerk just picked, which has no URL yet. Takes precedence: it is
  /// the newest thing they chose.
  final Uint8List? imageBytes;
  final double width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: SizedBox(
        width: width,
        height: height,
        child: Icon(Icons.image_outlined, color: colors.onSurfaceVariant),
      ),
    );

    Widget errorBuilder(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) => placeholder;

    if (imageBytes case final bytes?) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }

    if (imageUrl.trim().isEmpty) return placeholder;

    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }

    return Image.file(
      File(imageUrl),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
}
