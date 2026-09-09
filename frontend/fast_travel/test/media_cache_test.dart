import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fast_travel/Services/media_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cacheDirectory;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    cacheDirectory = await Directory.systemTemp.createTemp('fast_travel_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => cacheDirectory.path);
  });
  tearDownAll(() async {
    await MediaCache.manager.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    await cacheDirectory.delete(recursive: true);
  });

  test('public images share a bounded cache and bounded raster decoding', () {
    MediaCache.initialize();
    final first = MediaCache.imageProvider(
      'https://example.com/photo.jpg',
      cacheWidth: 8000,
    ) as ResizeImage;
    final second = MediaCache.imageProvider('https://example.com/avatar.jpg')
        as ResizeImage;
    expect(first.width, 1600);
    expect(first.imageProvider, isA<CachedNetworkImageProvider>());
    expect(
      (first.imageProvider as CachedNetworkImageProvider).cacheManager,
      same((second.imageProvider as CachedNetworkImageProvider).cacheManager),
    );
    expect(MediaCache.maxObjects, 200);
    expect(MediaCache.stalePeriod, const Duration(days: 7));
    expect(PaintingBinding.instance.imageCache.maximumSize, 80);
    expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes, 64 * 1024 * 1024);
  });

  test('local/private file schemes are not accepted by the public cache', () {
    expect(
      () => MediaCache.imageProvider('file:///private/voice.aac'),
      throwsArgumentError,
    );
  });
}
