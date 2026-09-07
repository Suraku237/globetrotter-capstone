import 'dart:async';
import 'dart:collection';

import 'package:fast_travel/Services/api_service.dart';
import 'package:fast_travel/Services/call_coordinator.dart';
import 'package:fast_travel/Services/call_push_service.dart';
import 'package:fast_travel/Services/session_state.dart';
import 'package:fast_travel/models/call_models.dart';
import 'package:fast_travel/models/models.dart';
import 'package:fast_travel/screens/friends/call_screen.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';

class _User extends Fake implements AppUser {
  @override
  final String id;

  _User([this.id = 'bob']);
}

class _Session extends Fake implements SessionState {
  final listeners = <VoidCallback>[];
  AppUser? user = _User();

  @override
  AppUser? get currentUser => user;

  @override
  bool get isSignedIn => user != null;

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  void changeUser(AppUser? next) {
    user = next;
    for (final listener in List<VoidCallback>.of(listeners)) {
      listener();
    }
  }
}

CallSession _call(
        {String status = 'ringing',
        bool expired = false,
        CallKind kind = CallKind.voice}) =>
    CallSession(
      id: 'call-id',
      kind: kind,
      targetType: 'direct',
      targetId: 'bob',
      title: 'Alice',
      callerId: 'alice',
      callerName: 'Alice',
      callerAvatarUrl: null,
      status: status,
      expiresAt: expired ? DateTime.utc(2000) : DateTime.utc(2099),
      participantIds: const ['alice', 'bob'],
      acceptedIds: const ['alice'],
      endedReason: status == 'ended' ? 'cancelled' : null,
    );

class _Api extends Fake implements ApiService {
  CallSession call = _call();
  final actions = <String>[];
  Completer<List<CallSession>>? pendingIncoming;
  final pendingConnection = Completer<CallConnection>();
  bool connecting = false;

  @override
  bool get isAuthenticated => true;

  @override
  Future<List<CallSession>> getIncomingCalls() async {
    final pending = pendingIncoming;
    if (pending != null) return pending.future;
    return call.isEnded ? [] : [call];
  }

  @override
  Future<CallSession> getCall(String id) async => call;

  @override
  Future<CallSession> createCall({
    required CallKind kind,
    required String targetType,
    required String targetId,
  }) async =>
      _call();

  @override
  Future<CallConnection> connectCall(String id, {required bool accept}) {
    connecting = true;
    return pendingConnection.future;
  }

  @override
  Future<CallSession> updateCall(String id, String action) async {
    actions.add(action);
    if (action != 'heartbeat') call = call.endedLocally();
    return call;
  }
}

class _Push extends Fake implements CallPushService {
  final ended = <String>[];
  int registrations = 0;
  int unregistrations = 0;
  Future<void> Function()? recover;
  final muteUpdates = <bool>[];
  bool initialMute = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> registerDevice() async => registrations++;

  @override
  Future<void> restoreSession() async {
    registrations++;
    await recover?.call();
  }

  @override
  Future<bool> getMuteState(String id) async => initialMute;

  @override
  Future<void> setMuted(String id, bool muted) async => muteUpdates.add(muted);

  @override
  Future<void> prepareAudio(String id) async {}

  @override
  Future<void> markConnected(String id) async {}

  @override
  Future<void> markMediaReady(String id) async {}

  @override
  Future<void> unregisterDevice() async => unregistrations++;

  @override
  Future<void> endCall(String id) async => ended.add(id);

  @override
  Future<void> markAccepting(String id) async {}

  @override
  Future<void> dispose() async {}
}

class _MediaParticipant extends Fake implements LocalParticipant {
  bool microphone = false;
  final microphoneRequests = <bool>[];
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
    microphoneRequests.add(enabled);
    microphone = enabled;
    return null;
  }

  @override
  Future<LocalTrackPublication?> setCameraEnabled(bool enabled,
      {CameraCaptureOptions? cameraCaptureOptions}) async {
    cameraRequests++;
    return null;
  }
}

class _MediaListener extends Fake implements EventsListener<RoomEvent> {
  @override
  Future<void> Function() on<E>(FutureOr<void> Function(E) then,
          {bool Function(E)? filter}) =>
      () async {};
  @override
  Future<bool> dispose() async => true;
}

class _MediaRoom extends Fake implements Room {
  final participant = _MediaParticipant();
  Completer<void>? connecting;
  int connections = 0;
  int disconnects = 0;
  int disposals = 0;
  ConnectionState state = ConnectionState.disconnected;
  @override
  ConnectionState get connectionState => state;
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
      _MediaListener();
  @override
  Future<void> connect(String url, String token,
      {ConnectOptions? connectOptions,
      RoomOptions? roomOptions,
      FastConnectOptions? fastConnectOptions}) async {
    connections++;
    state = ConnectionState.connecting;
    await connecting?.future;
    state = ConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    participant.microphone = false;
    state = ConnectionState.disconnected;
  }

  @override
  Future<bool> dispose() async {
    disposals++;
    return true;
  }
}

void main() {
  late _Api api;
  late _Push push;
  late _Session session;
  late CallCoordinator calls;

  CallConnection connection(CallSession call) => CallConnection(
      call: call, url: 'wss://example.livekit.cloud', token: 'test-token');

  void headless(_MediaRoom room) {
    api = _Api();
    push = _Push();
    session = _Session();
    calls = CallCoordinator(
      session: session,
      navigatorKey: GlobalKey<NavigatorState>(),
      messengerKey: GlobalKey<ScaffoldMessengerState>(),
      api: api,
      push: push,
      roomFactory: () => room,
      uiAvailable: false,
    );
  }

  testWidgets(
      'restored native answer connects with no scene, frame, or Navigator',
      (tester) async {
    final room = _MediaRoom();
    headless(room);
    api.call = _call(kind: CallKind.video);
    api.pendingConnection.complete(connection(api.call));
    final recovered = Completer<void>();
    push.recover = () async {
      await calls.acceptIncoming(api.call.id);
      recovered.complete();
    };
    await calls.initialize();
    await recovered.future;
    expect(calls.navigatorKey.currentState, isNull);
    expect(room.connections, 1);
    expect(room.participant.microphone, isTrue);
    expect(room.participant.cameraRequests, 0);
    expect(calls.media!.hasView, isFalse);
    await calls.signOut();
    expect(room.disconnects, 1);
    expect(room.disposals, 1);
    expect(push.unregistrations, 1);
    await calls.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets(
      'scene foreground renders the same headless Room without reconnecting',
      (tester) async {
    final room = _MediaRoom();
    headless(room);
    api.pendingConnection.complete(connection(api.call));
    await calls.initialize();
    await calls.acceptIncoming(api.call.id);
    final media = calls.media;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: calls.navigatorKey,
      scaffoldMessengerKey: calls.messengerKey,
      home: const Scaffold(body: Text('Home')),
    ));
    calls.setUiAvailable(true);
    await tester.pumpAndSettle();
    expect(find.byType(CallScreen), findsOneWidget);
    expect(
        tester.widget<CallScreen>(find.byType(CallScreen)).media, same(media));
    calls.setUiAvailable(false);
    await tester.pump();
    expect(room.participant.microphone, isTrue);
    calls.setUiAvailable(true);
    await tester.pumpAndSettle();
    expect(room.connections, 1);
    await calls.signOut();
    await tester.pumpAndSettle();
    expect(room.disposals, 1);
    await calls.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets(
      'cold native mute and mute while connecting never publish an open mic',
      (tester) async {
    final room = _MediaRoom()..connecting = Completer<void>();
    headless(room);
    push.initialMute = true;
    api.pendingConnection.complete(connection(api.call));
    await calls.initialize();
    final accepting = calls.acceptIncoming(api.call.id);
    await tester.pump();
    await calls.updateNativeMute(api.call.id, false);
    await calls.updateNativeMute(api.call.id, true);
    room.connecting!.complete();
    await accepting;
    expect(room.participant.microphoneRequests, [false]);
    await calls.updateNativeMute(api.call.id, false);
    expect(room.participant.microphone, isTrue);
    expect(push.muteUpdates, isEmpty);
    await calls.media!.setMuted(true);
    expect(room.participant.microphone, isFalse);
    expect(push.muteUpdates, [true]);
    await calls.updateNativeMute(api.call.id, true);
    expect(push.muteUpdates, [true]);
    expect(room.participant.microphoneRequests, [false, true, false]);
    await calls.signOut();
    await calls.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets(
      'native cancellation invalidates a pending headless backend accept',
      (tester) async {
    final room = _MediaRoom();
    headless(room);
    final offered = api.call;
    await calls.initialize();
    final accepting = calls.acceptIncoming(offered.id);
    await tester.pump();
    expect(api.connecting, isTrue);
    await calls.endIncoming(offered.id);
    api.pendingConnection.complete(connection(offered));
    await accepting;
    expect(room.connections, 0);
    expect(room.participant.microphoneRequests, isEmpty);
    expect(calls.media, isNull);
    expect(api.actions, contains('leave'));
    await calls.dispose();
  });

  testWidgets('native end during Room.connect cannot publish late media',
      (tester) async {
    final room = _MediaRoom()..connecting = Completer<void>();
    headless(room);
    api.pendingConnection.complete(connection(api.call));
    await calls.initialize();
    final accepting = calls.acceptIncoming(api.call.id);
    await tester.pump();
    final ending = calls.endIncoming(api.call.id);
    await tester.pump();
    expect(calls.media!.closing, isTrue);
    room.connecting!.complete();
    await accepting;
    await ending;
    expect(room.participant.microphoneRequests, isEmpty);
    expect(room.disposals, 1);
    expect(calls.media, isNull);
    await calls.dispose();
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('no restored credentials cannot consume a lock-screen accept',
      (tester) async {
    final room = _MediaRoom();
    headless(room);
    session.user = null;
    await calls.initialize();
    await calls.signOut();
    await calls.acceptIncoming(api.call.id);
    expect(push.unregistrations, 1);
    expect(api.connecting, isFalse);
    expect(room.connections, 0);
    await calls.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final messenger = GlobalKey<ScaffoldMessengerState>();
    api = _Api();
    push = _Push();
    session = _Session();
    calls = CallCoordinator(
      session: session,
      navigatorKey: navigator,
      messengerKey: messenger,
      api: api,
      push: push,
    );
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      scaffoldMessengerKey: messenger,
      home: const Scaffold(body: Text('Any app tab')),
    ));
  }

  testWidgets('incoming call appears globally and decline sends real action',
      (tester) async {
    await mount(tester);
    await calls.initialize();
    await tester.pumpAndSettle();
    expect(find.text('Incoming voice call'), findsOneWidget);
    expect(find.text('Alice is calling'), findsOneWidget);
    expect(push.registrations, 1);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(api.actions, ['decline']);
    expect(push.ended, ['call-id']);
    expect(calls.callState.value, isNull);
    expect(find.text('Incoming voice call'), findsNothing);
    await calls.dispose();
  });

  testWidgets('cancelled calls remove the incoming prompt on the next poll',
      (tester) async {
    await mount(tester);
    await calls.initialize();
    await tester.pumpAndSettle();
    api.call = _call(status: 'ended');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Incoming voice call'), findsNothing);
    expect(calls.callState.value, isNull);
    expect(push.ended, ['call-id']);
    await calls.dispose();
  });

  testWidgets('expired calls never display an answer prompt', (tester) async {
    await mount(tester);
    api.call = _call(expired: true);
    await calls.initialize();
    await tester.pumpAndSettle();
    expect(find.text('Answer'), findsNothing);
    expect(calls.callState.value, isNull);
    await calls.dispose();
  });

  testWidgets('signing out releases the call and unregisters notifications',
      (tester) async {
    await mount(tester);
    await calls.initialize();
    await tester.pumpAndSettle();
    await calls.signOut();
    await tester.pumpAndSettle();
    expect(api.actions, ['leave']);
    expect(push.unregistrations, 1);
    expect(calls.callState.value, isNull);
    expect(find.text('Incoming voice call'), findsNothing);
    await calls.dispose();
  });

  testWidgets('late polling response cannot show a call after sign out',
      (tester) async {
    await mount(tester);
    final pending = Completer<List<CallSession>>();
    api.pendingIncoming = pending;
    await calls.initialize();
    await tester.pump();
    await calls.signOut();
    pending.complete([_call()]);
    await tester.pumpAndSettle();
    expect(find.text('Incoming voice call'), findsNothing);
    expect(calls.callState.value, isNull);
    await calls.dispose();
  });

  for (final nextUser in ['bob', 'another-account']) {
    testWidgets('late token cannot reopen a call after signing in as $nextUser',
        (tester) async {
      await mount(tester);
      api.call = _call(status: 'ended');
      await calls.initialize();
      await tester.pumpAndSettle();
      final starting = calls.startCall(
        kind: CallKind.voice,
        targetType: 'direct',
        targetId: 'alice',
      );
      await tester.pump();
      expect(api.connecting, isTrue);
      await calls.signOut();
      session.changeUser(null);
      await tester.pump();
      session.changeUser(_User(nextUser));
      await tester.pump();
      api.pendingConnection.complete(CallConnection(
        call: _call(),
        url: 'wss://example.livekit.cloud',
        token: 'old-account-token',
      ));
      await starting;
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsNothing);
      expect(calls.callState.value, isNull);
      await calls.dispose();
    });
  }
}
