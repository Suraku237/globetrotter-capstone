import 'dart:async';

import 'package:fast_travel/Services/media_playback.dart';
import 'package:fast_travel/Services/media_settings.dart';
import 'package:fast_travel/models/models.dart';
import 'package:fast_travel/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The existing video_player plugin's test interface; no real platform media.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  int created = 0;
  int played = 0;
  int paused = 0;
  bool initializeAutomatically = true;
  final events = <int, StreamController<VideoEvent>>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++created;
    events[id] = StreamController<VideoEvent>();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (initializeAutomatically) initializePlayer(playerId);
    return events[playerId]!.stream;
  }

  void initializePlayer(int id) {
    events[id]!.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: const Size(360, 640),
    ));
  }

  @override
  Future<void> dispose(int playerId) async {
    await events.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async {
    played++;
  }

  @override
  Future<void> pause(int playerId) async {
    paused++;
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
}

Post _post(String id) => Post(
      id: id,
      userId: 'author',
      authorName: 'Traveller',
      text: 'A trip',
      video: '/uploads/$id.mp4',
      createdAt: '',
      likes: [],
      comments: [],
    );

Widget _card({bool active = true, String id = 'post'}) => MaterialApp(
      home: Scaffold(
        body: PostCard(
          post: _post(id),
          currentUserId: 'viewer',
          isActive: active,
          onLike: () {},
          onOpenComments: () {},
          showActionRail: false,
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _VideoPlatform platform;
  late VideoPlayerPlatform originalPlatform;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MediaSettings.instance.setDataSaver(true);
    MediaPlayback.suspended.value = false;
    originalPlatform = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalPlatform;
  });

  testWidgets('Data Saver creates no video player until an explicit play tap',
      (tester) async {
    await tester.pumpWidget(_card());
    await tester.pump(const Duration(seconds: 2));
    expect(platform.created, 0);
    expect(find.text('Tap to play'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byKey(const ValueKey('video-play')));
    await tester.pump();
    expect(platform.created, 1);
    expect(platform.played, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('opt-out initializes only the active page', (tester) async {
    await MediaSettings.instance.setDataSaver(false);
    await tester.pumpWidget(_card(active: false));
    await tester.pump();
    expect(platform.created, 0);
    await tester.pumpWidget(_card());
    await tester.pump();
    expect(platform.created, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('explicit playback respects page, call and lifecycle suspension',
      (tester) async {
    await tester.pumpWidget(_card());
    await tester.tap(find.byKey(const ValueKey('video-play')));
    await tester.pump();
    final firstPlays = platform.played;
    await tester.pumpWidget(_card(active: false));
    await tester.pump();
    expect(platform.paused, greaterThan(0));
    MediaPlayback.suspended.value = true;
    await tester.pumpWidget(_card());
    await tester.pump();
    expect(platform.played, firstPlays);
    MediaPlayback.suspended.value = false;
    await tester.pump();
    expect(platform.played, greaterThan(firstPlays));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final pausedCount = platform.paused;
    expect(pausedCount, greaterThan(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.played, greaterThan(firstPlays + 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('initialization errors show Retry and retry creates one player',
      (tester) async {
    platform.initializeAutomatically = false;
    await tester.pumpWidget(_card());
    await tester.tap(find.byKey(const ValueKey('video-play')));
    await tester.pump();
    platform.events[1]!.addError(PlatformException(code: 'load_failed', message: 'Video unavailable'));
    await tester.pump();
    expect(find.text('Loading failed · Retry'), findsOneWidget);
    platform.initializeAutomatically = true;
    await tester.tap(find.byKey(const ValueKey('video-play')));
    await tester.pump();
    expect(platform.created, 2);
    expect(platform.played, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a different post requires a new explicit tap', (tester) async {
    await tester.pumpWidget(_card());
    await tester.tap(find.byKey(const ValueKey('video-play')));
    await tester.pump();
    await tester.pumpWidget(_card(id: 'next'));
    await tester.pump();
    expect(platform.created, 1);
    expect(find.text('Tap to play'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('enabling Data Saver cancels unrequested initialization',
      (tester) async {
    platform.initializeAutomatically = false;
    await MediaSettings.instance.setDataSaver(false);
    await tester.pumpWidget(_card());
    await tester.pump();
    expect(platform.created, 1);
    await MediaSettings.instance.setDataSaver(true);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(platform.events, isEmpty);
    expect(platform.played, 0);
    expect(find.text('Tap to play'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('stalled initialization becomes retryable and releases the player',
      (tester) async {
    platform.initializeAutomatically = false;
    await tester.pumpWidget(_card());
    await tester.tap(find.byKey(const ValueKey('video-play')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Loading failed · Retry'), findsOneWidget);
    expect(platform.events, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving an initializing video cancels its download in Data Saver',
      (tester) async {
    platform.initializeAutomatically = false;
    await tester.pumpWidget(_card());
    await tester.tap(find.byKey(const ValueKey('video-play')));
    await tester.pump();
    await tester.pumpWidget(_card(active: false));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(platform.events, isEmpty);
    await tester.pumpWidget(_card());
    await tester.pump();
    expect(platform.created, 1);
    expect(find.text('Tap to play'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
