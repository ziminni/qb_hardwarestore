import 'dart:io';

import 'package:flutter/material.dart';

class ProductsImage extends StatelessWidget {
  const ProductsImage({
    super.key,
    required this.imageUrl,
    this.width = 48,
    this.height = 48,
    this.fit = BoxFit.cover,
  });

  final String imageUrl;
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

    if (imageUrl.trim().isEmpty) return placeholder;

    Widget errorBuilder(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) => placeholder;

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
