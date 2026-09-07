import 'dart:async';
import 'dart:collection';

import 'package:fast_travel/models/call_models.dart';
import 'package:fast_travel/Services/call_media_session.dart';
import 'package:fast_travel/screens/friends/call_screen.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';

class _Participant extends Fake implements LocalParticipant {
  bool microphone = false;
  bool denyMicrophone = false;
  bool denyCamera = false;
  int cameraRequests = 0;

  @override
  String get identity => 'bob';
  @override
  String get name => 'Bob';
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  bool isMicrophoneEnabled() => microphone;
  @override
  bool isCameraEnabled() => false;
  @override
  List<LocalTrackPublication<LocalVideoTrack>> get videoTrackPublications => [];

  @override
  Future<LocalTrackPublication?> setMicrophoneEnabled(bool enabled,
      {AudioCaptureOptions? audioCaptureOptions}) async {
    if (denyMicrophone) {
      // Match flutter_webrtc's native getUserMedia error contract.
      // ignore: only_throw_errors
      throw 'NotAllowedError';
    }
    microphone = enabled;
    return null;
  }

  @override
  Future<LocalTrackPublication?> setCameraEnabled(bool enabled,
      {CameraCaptureOptions? cameraCaptureOptions}) async {
    cameraRequests++;
    if (denyCamera) {
      // ignore: only_throw_errors
      throw 'Camera permission denied';
    }
    return null;
  }
}

class _Listener extends Fake implements EventsListener<RoomEvent> {
  @override
  Future<void> Function() on<E>(FutureOr<void> Function(E) then,
          {bool Function(E)? filter}) =>
      () async {};

  @override
  Future<bool> dispose() async => true;
}

class _Room extends Fake implements Room {
  final operations = <String>[];
  final participant = _Participant();
  int disconnects = 0;
  int disposals = 0;

  @override
  ConnectionState get connectionState => ConnectionState.connected;
  @override
  LocalParticipant get localParticipant => participant;
  @override
  UnmodifiableMapView<String, RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView({});
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  EventsListener<RoomEvent> createListener({bool synchronized = false}) =>
      _Listener();

  @override
  Future<void> connect(String url, String token,
      {ConnectOptions? connectOptions,
      RoomOptions? roomOptions,
      FastConnectOptions? fastConnectOptions}) async {
    operations.add('connect');
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    participant.microphone = false;
  }

  @override
  Future<bool> dispose() async {
    disposals++;
    return true;
  }
}

CallSession _call(CallKind kind) => CallSession(
      id: 'call-id',
      kind: kind,
      targetType: 'direct',
      targetId: 'alice',
      title: 'Alice',
      callerId: 'bob',
      callerName: 'Bob',
      callerAvatarUrl: null,
      status: 'ringing',
      expiresAt: DateTime.utc(2099),
      participantIds: const ['alice', 'bob'],
      acceptedIds: const ['bob'],
      endedReason: null,
    );

void main() {
  testWidgets('a detached shared call view does not stop or recreate media',
      (tester) async {
    final room = _Room();
    final state = ValueNotifier<CallSession?>(_call(CallKind.voice));
    final connection = CallConnection(
      call: state.value!,
      url: 'wss://example.livekit.cloud',
      token: 'test-token',
    );
    final media = CallMediaSession(connection: connection, room: room);
    await media.start();
    Widget view() => MaterialApp(
          home: CallScreen(
            connection: connection,
            media: media,
            currentUserId: 'bob',
            callState: state,
            onLeave: () async {},
          ),
        );
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(media.hasView, isFalse);
    expect(room.participant.microphone, isTrue);
    expect(room.disconnects, 0);
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(room.operations, ['connect']);
    expect(media.hasView, isTrue);
    await media.stop();
    await tester.pumpWidget(const SizedBox());
    expect(room.disposals, 1);
    state.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  Future<void> mount(
    WidgetTester tester,
    _Room room,
    ValueNotifier<CallSession?> state, {
    Future<void> Function()? prepareAudio,
    Future<void> Function()? onConnected,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: CallScreen(
        room: room,
        connection: CallConnection(
          call: state.value!,
          url: 'wss://example.livekit.cloud',
          token: 'test-token',
        ),
        currentUserId: 'bob',
        callState: state,
        onLeave: () async => state.value = state.value!.endedLocally(),
        prepareAudio: prepareAudio,
        onConnected: onConnected,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('native microphone denial still disconnects and disposes room',
      (tester) async {
    final room = _Room()..participant.denyMicrophone = true;
    final state = ValueNotifier<CallSession?>(_call(CallKind.voice));
    await mount(tester, room, state);
    expect(
        find.textContaining('Microphone or audio unavailable'), findsOneWidget);
    expect(state.value!.isEnded, isTrue);
    expect(room.disconnects, 1);
    expect(room.disposals, 1);
    expect(room.participant.microphone, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(room.disposals, 1);
    state.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('camera denial is visible and audio stops when screen is removed',
      (tester) async {
    final room = _Room()..participant.denyCamera = true;
    final state = ValueNotifier<CallSession?>(_call(CallKind.video));
    await mount(tester, room, state);
    expect(find.textContaining('Camera unavailable'), findsOneWidget);
    expect(room.participant.microphone, isTrue);
    expect(state.value!.isEnded, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(room.participant.microphone, isFalse);
    expect(room.disconnects, 1);
    expect(room.disposals, 1);
    state.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('voice calls publish and mute audio without opening the camera',
      (tester) async {
    final room = _Room();
    final state = ValueNotifier<CallSession?>(_call(CallKind.voice));
    await mount(tester, room, state);
    expect(room.participant.microphone, isTrue);
    expect(room.participant.cameraRequests, 0);
    await tester.tap(find.byTooltip('Mute'));
    await tester.pumpAndSettle();
    expect(room.participant.microphone, isFalse);
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pumpAndSettle();
    expect(room.participant.microphone, isTrue);
    state.value = state.value!.endedLocally();
    await tester.pumpAndSettle();
    expect(room.participant.microphone, isFalse);
    expect(room.disposals, 1);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets(
      'native audio is prepared before joining and marked connected after',
      (tester) async {
    final room = _Room();
    final state = ValueNotifier<CallSession?>(_call(CallKind.voice));
    await mount(
      tester,
      room,
      state,
      prepareAudio: () async => room.operations.add('prepare'),
      onConnected: () async => room.operations.add('connected'),
    );
    expect(room.operations, ['prepare', 'connect', 'connected']);
    expect(room.participant.microphone, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(room.participant.microphone, isFalse);
    state.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('ending while native audio prepares never opens the microphone',
      (tester) async {
    final room = _Room();
    final state = ValueNotifier<CallSession?>(_call(CallKind.voice));
    final ready = Completer<void>();
    await mount(tester, room, state, prepareAudio: () => ready.future);
    state.value = state.value!.endedLocally();
    ready.complete();
    await tester.pumpAndSettle();
    expect(room.operations, isEmpty);
    expect(room.participant.microphone, isFalse);
    expect(room.disposals, 1);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
}
