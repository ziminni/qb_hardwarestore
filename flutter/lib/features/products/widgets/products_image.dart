import 'dart:io';
import 'dart:typed_data';

import 'package:client/core/config/api_config.dart';
import 'package:flutter/material.dart';

class ProductsImage extends StatelessWidget {
  const ProductsImage({
    super.key,
    this.imageUrl = '',
    this.imageBytes,
    this.width = 48,
    this.height = 48,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  /// The server's `image_url`, or a legacy device path.
  final String imageUrl;

  /// A photo the clerk just picked, which has no URL yet. Takes precedence: it is
  /// the newest thing they chose.
  final Uint8List? imageBytes;
  final double width;
  final double height;
  final BoxFit fit;

  /// Optional custom placeholder rendered when no image is set or loading fails.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback =
        placeholder ??
        ColoredBox(
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
    ) => fallback;

    if (imageBytes case final bytes?) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }

    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return fallback;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }

    // Relative server media URLs (e.g. `/media/product-images/...`) resolve
    // against the configured API host rather than the local filesystem.
    if (trimmed.startsWith('/media/')) {
      final root = ApiConfig.baseUrl.endsWith('/')
          ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
          : ApiConfig.baseUrl;
      return Image.network(
        '$root$trimmed',
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }

    return Image.file(
      File(trimmed),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
}
