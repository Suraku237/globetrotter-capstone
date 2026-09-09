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
  final updates = StreamController<Set<String>>.broadcast();
  @override
  Stream<Set<String>> get changes => updates.stream;
  @override
  bool isLive = false;

  CallSession call = _call();
  final actions = <String>[];
  int incomingReads = 0;
  int callReads = 0;
  bool publishHeartbeat = false;
  Completer<List<CallSession>>? pendingIncoming;
  Completer<CallSession>? pendingCall;
  Completer<CallSession>? pendingAction;
  final pendingConnection = Completer<CallConnection>();
  bool connecting = false;

  @override
  bool get isAuthenticated => true;

  @override
  Future<List<CallSession>> getIncomingCalls() async {
    incomingReads++;
    final pending = pendingIncoming;
    if (pending != null) return pending.future;
    return call.isEnded ? [] : [call];
  }

  @override
  Future<CallSession> getCall(String id) async {
    callReads++;
    if (pendingCall != null) return pendingCall!.future;
    return call;
  }

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
    if (pendingAction != null) return pendingAction!.future;
    if (action != 'heartbeat') call = call.endedLocally();
    if (action == 'heartbeat' && publishHeartbeat) updates.add({'calls'});
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

  void headless(WidgetTester tester, _MediaRoom room) {
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
      now: tester.binding.clock.now,
      uiAvailable: false,
    );
  }

  Future<void> disposeCalls(WidgetTester tester) async {
    // Stream cancellation crosses zones; finish teardown outside FakeAsync.
    await tester.runAsync(() async {
      await calls.dispose();
      await api.updates.close();
    });
  }

  testWidgets(
      'restored native answer connects with no scene, frame, or Navigator',
      (tester) async {
    final room = _MediaRoom();
    headless(tester, room);
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
    await disposeCalls(tester);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets(
      'scene foreground renders the same headless Room without reconnecting',
      (tester) async {
    final room = _MediaRoom();
    headless(tester, room);
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
    await disposeCalls(tester);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets(
      'cold native mute and mute while connecting never publish an open mic',
      (tester) async {
    final room = _MediaRoom()..connecting = Completer<void>();
    headless(tester, room);
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
    await disposeCalls(tester);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets(
      'native cancellation invalidates a pending headless backend accept',
      (tester) async {
    final room = _MediaRoom();
    headless(tester, room);
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
    await disposeCalls(tester);
  });

  testWidgets('native end during Room.connect cannot publish late media',
      (tester) async {
    final room = _MediaRoom()..connecting = Completer<void>();
    headless(tester, room);
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
    await disposeCalls(tester);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('no restored credentials cannot consume a lock-screen accept',
      (tester) async {
    final room = _MediaRoom();
    headless(tester, room);
    session.user = null;
    await calls.initialize();
    await calls.signOut();
    await calls.acceptIncoming(api.call.id);
    expect(push.unregistrations, 1);
    expect(api.connecting, isFalse);
    expect(room.connections, 0);
    await disposeCalls(tester);
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
      now: tester.binding.clock.now,
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
    await disposeCalls(tester);
  });

  for (final topic in ['calls', 'all']) {
    testWidgets('$topic event immediately presents an incoming call',
        (tester) async {
      await mount(tester);
      api.isLive = true;
      api.call = _call(status: 'ended');
      await calls.initialize();
      await tester.pumpAndSettle();
      expect(api.incomingReads, 1);

      api.call = _call();
      api.updates.add({topic});
      await tester.pumpAndSettle();

      expect(api.incomingReads, 2);
      expect(find.text('Incoming voice call'), findsOneWidget);
      await disposeCalls(tester);
    });
  }

  testWidgets(
      'connected idle polls every 30 seconds and falls back to 3 seconds',
      (tester) async {
    await mount(tester);
    api.isLive = true;
    api.call = _call(status: 'ended');
    await calls.initialize();
    await tester.pumpAndSettle();
    expect(api.incomingReads, 1);

    api.updates.add({'chat'});
    await tester.pump(const Duration(seconds: 3));
    expect(api.incomingReads, 1);
    await tester.pump(const Duration(seconds: 27));
    expect(api.incomingReads, 2);

    api.isLive = false;
    await tester.pump(const Duration(seconds: 3));
    expect(api.incomingReads, 3);
    await disposeCalls(tester);
  });

  testWidgets('background idle defers events until foreground resumes',
      (tester) async {
    await mount(tester);
    api.call = _call(status: 'ended');
    await calls.initialize();
    await tester.pumpAndSettle();

    calls.didChangeAppLifecycleState(AppLifecycleState.paused);
    api.call = _call();
    api.updates.add({'calls'});
    await tester.pump(const Duration(seconds: 30));
    expect(api.incomingReads, 1);
    expect(find.text('Incoming voice call'), findsNothing);

    calls.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.incomingReads, 2);
    expect(find.text('Incoming voice call'), findsOneWidget);
    await disposeCalls(tester);
  });

  testWidgets('events during incoming polling coalesce into one fresh request',
      (tester) async {
    await mount(tester);
    final pending = Completer<List<CallSession>>();
    api.pendingIncoming = pending;
    await calls.initialize();
    await tester.pump();
    expect(api.incomingReads, 1);

    api.updates.add({'calls'});
    api.updates.add({'all'});
    await tester.pump();
    expect(api.incomingReads, 1);

    api.pendingIncoming = null;
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(api.incomingReads, 2);
    expect(find.text('Incoming voice call'), findsOneWidget);
    await disposeCalls(tester);
  });

  testWidgets('active polling drains events that arrived during a stale read',
      (tester) async {
    await mount(tester);
    await calls.initialize();
    await tester.pumpAndSettle();
    final pending = Completer<CallSession>();
    api.pendingCall = pending;

    api.updates.add({'calls'});
    await tester.pump();
    expect(api.callReads, 1);
    api.call = _call(status: 'ended');
    api.updates.add({'calls'});
    api.updates.add({'all'});
    await tester.pump();
    expect(api.callReads, 1);

    api.pendingCall = null;
    pending.complete(_call(status: 'active'));
    await tester.pumpAndSettle();
    expect(api.callReads, 2);
    expect(calls.callState.value, isNull);
    expect(find.text('Incoming voice call'), findsNothing);
    expect(push.ended, ['call-id']);
    await disposeCalls(tester);
  });

  for (final outgoing in [false, true]) {
    testWidgets(
        'events during ${outgoing ? 'start' : 'accept'} refresh on completion',
        (tester) async {
      final room = _MediaRoom();
      headless(tester, room);
      api.isLive = true;
      api.call = _call(status: 'ended');
      await calls.initialize();
      await tester.pump();
      final offered = _call(status: 'active');
      final connecting = outgoing
          ? calls.startCall(
              kind: CallKind.voice,
              targetType: 'direct',
              targetId: 'alice',
            )
          : calls.acceptIncoming(offered.id);
      await tester.pump();
      expect(api.connecting, isTrue);

      api.updates.add({'calls'});
      api.updates.add({'all'});
      await tester.pump();
      expect(api.callReads, 0);
      api.pendingConnection.complete(connection(offered));
      await connecting;
      await tester.pump();

      expect(api.callReads, 1);
      expect(room.connections, 1);
      expect(room.disposals, 1);
      expect(calls.media, isNull);
      expect(calls.callState.value, isNull);
      await disposeCalls(tester);
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
  }

  testWidgets('events while declining refresh after releasing busy state',
      (tester) async {
    await mount(tester);
    await calls.initialize();
    await tester.pumpAndSettle();
    final pending = Completer<CallSession>();
    api.pendingAction = pending;
    final declining = calls.endIncoming(api.call.id);
    await tester.pump();
    api.updates.add({'calls'});
    api.updates.add({'all'});
    await tester.pump();
    expect(api.incomingReads, 1);

    api.call = _call(status: 'ended');
    pending.complete(api.call);
    await declining;
    await tester.pumpAndSettle();
    expect(api.incomingReads, 2);
    expect(calls.callState.value, isNull);
    await disposeCalls(tester);
  });

  testWidgets(
      'heartbeat invalidation refreshes without a heartbeat feedback loop',
      (tester) async {
    final room = _MediaRoom();
    headless(tester, room);
    api.isLive = true;
    api.publishHeartbeat = true;
    api.call = _call(status: 'active');
    api.pendingConnection.complete(connection(api.call));
    await calls.initialize();
    await calls.acceptIncoming(api.call.id);
    await tester.pump();
    final initialReads = api.callReads;

    calls.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 9));
    expect(api.actions, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    expect(api.actions, ['heartbeat']);
    expect(api.callReads, initialReads + 1);

    await tester.pump(const Duration(seconds: 3));
    expect(api.actions, ['heartbeat']);
    expect(api.callReads, initialReads + 1);
    api.call = _call(status: 'ended');
    api.updates.add({'calls'});
    await tester.pump();
    expect(calls.callState.value, isNull);
    expect(room.disposals, 1);
    await disposeCalls(tester);
  }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets(
      'dispose removes realtime and session listeners and cancels polling',
      (tester) async {
    await mount(tester);
    api.call = _call(status: 'ended');
    await calls.initialize();
    await tester.pumpAndSettle();
    expect(api.updates.hasListener, isTrue);

    await tester.runAsync(calls.dispose);
    expect(api.updates.hasListener, isFalse);
    expect(session.listeners, isEmpty);
    api.updates.add({'calls'});
    await tester.pump(const Duration(seconds: 30));
    expect(api.incomingReads, 1);
    await tester.runAsync(api.updates.close);
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
    await disposeCalls(tester);
  });

  testWidgets('expired calls never display an answer prompt', (tester) async {
    await mount(tester);
    api.call = _call(expired: true);
    await calls.initialize();
    await tester.pumpAndSettle();
    expect(find.text('Answer'), findsNothing);
    expect(calls.callState.value, isNull);
    await disposeCalls(tester);
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
    await disposeCalls(tester);
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
    await disposeCalls(tester);
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
      await disposeCalls(tester);
    });
  }
}
