import 'package:flutter/material.dart';

import '../Services/media_cache.dart';

/// Shared photo rendering without authentication headers or media prefetch.
class PublicNetworkImage extends StatelessWidget {
  const PublicNetworkImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.errorBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return errorBuilder?.call(context, StateError('No image'), null) ??
          const Icon(Icons.broken_image_outlined);
    }
    return Image(
      image: MediaCache.imageProvider(
        url,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
      ),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: errorBuilder ??
          (_, __, ___) => const Icon(Icons.broken_image_outlined),
    );
  }
}
