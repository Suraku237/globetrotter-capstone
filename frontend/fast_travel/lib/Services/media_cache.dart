import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Public photos/avatars only. Never pass authenticated voice/video URLs here.
/// Native platforms persist files; web uses the browser's HTTP image cache.
class MediaCache {
  static const maxObjects = 200;
  static const stalePeriod = Duration(days: 7);
  static CacheManager? _manager;

  static CacheManager get manager => _manager ??= CacheManager(
        Config(
          'fast_travel_public_images_v1',
          stalePeriod: stalePeriod,
          maxNrOfCacheObjects: maxObjects,
        ),
      );

  static void initialize() {
    PaintingBinding.instance.imageCache
      ..maximumSize = 80
      ..maximumSizeBytes = 64 * 1024 * 1024;
  }

  static ImageProvider imageProvider(
    String publicUrl, {
    int? cacheWidth,
    int? cacheHeight,
  }) {
    final uri = Uri.tryParse(publicUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(publicUrl, 'publicUrl', 'Expected an HTTP image');
    }
    return ResizeImage.resizeIfNeeded(
      (cacheWidth ?? 1024).clamp(1, 1600),
      cacheHeight?.clamp(1, 1600),
      CachedNetworkImageProvider(publicUrl, cacheManager: manager),
    );
  }

  static Future<void> clear() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await manager.emptyCache();
  }
}
