import 'dart:async';

import 'package:fast_travel/Services/api_service.dart';
import 'package:fast_travel/Services/call_coordinator.dart';
import 'package:fast_travel/models/call_models.dart';
import 'package:fast_travel/screens/chat/community_call_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CallSession _call(CallKind kind) => CallSession.fromJson({
      'id': 'public-call',
      'kind': kind.name,
      'target_type': 'community',
      'target_id': 'community',
      'title': 'Community',
      'caller_id': 'alice',
      'caller_name': 'Alice',
      'status': 'active',
      'expires_at': '2000-01-01T00:00:00Z',
      'participant_ids': ['alice'],
      'accepted_ids': ['alice'],
    });

class _Api extends Fake implements ApiService {
  final events = StreamController<Set<String>>.broadcast();
  CallSession? active;
  ApiException? failure;
  int reads = 0;
  @override
  bool isLive = true;
  @override
  Stream<Set<String>> get changes => events.stream;
  @override
  void refreshTopics(Set<String> topics) => events.add(topics);
  @override
  Future<CallSession?> getCommunityCall() async {
    reads++;
    if (failure != null) throw failure!;
    return active;
  }
}

class _Calls extends Fake implements CallCoordinator {
  @override
  final callState = ValueNotifier<CallSession?>(null);
  @override
  bool get isInCall => callState.value != null;
  final starts = <CallKind>[];
  final joins = <String>[];
  @override
  Future<void> startCall({
    required CallKind kind,
    required String targetType,
    required String targetId,
  }) async {
    expect(targetType, 'community');
    expect(targetId, 'community');
    starts.add(kind);
  }

  @override
  Future<void> joinCommunityCall(String id) async => joins.add(id);
}

void main() {
  late _Api api;
  late _Calls calls;
  var canCall = true;
  var prepared = 0;

  setUp(() {
    api = _Api();
    calls = _Calls();
    canCall = true;
    prepared = 0;
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: CommunityCallBar(
        api: api,
        calls: calls,
        beforeCall: () async {
          prepared++;
          return canCall;
        },
      ),
    )));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => api.events.close());
    calls.callState.dispose();
  }

  for (final kind in CallKind.values) {
    testWidgets('${kind.name} starts a public call only after a tap',
        (tester) async {
      await show(tester);
      expect(calls.starts, isEmpty);
      await tester
          .tap(find.text(kind == CallKind.voice ? 'Voice call' : 'Video call'));
      await tester.pumpAndSettle();
      expect(calls.starts, [kind]);
      expect(prepared, 1);
      await close(tester);
    });
  }

  testWidgets('live banner supports late opt-in join and disappears on end',
      (tester) async {
    await show(tester);
    api.active = _call(CallKind.video);
    api.events.add({'community_calls'});
    await tester.pumpAndSettle();
    expect(find.text('Video call - 1 joined'), findsOneWidget);
    expect(calls.joins, isEmpty);
    await tester.tap(find.text('Join call'));
    await tester.pumpAndSettle();
    expect(calls.joins, ['public-call']);
    api.active = null;
    api.events.add({'community_calls'});
    await tester.pumpAndSettle();
    expect(find.text('Join call'), findsNothing);
    expect(find.text('Voice call'), findsOneWidget);
    await close(tester);
  });

  testWidgets('offline failure hides stale join action and retries explicitly',
      (tester) async {
    api.active = _call(CallKind.voice);
    await show(tester);
    api.failure = ApiException('Cannot reach the call server.');
    api.events.add({'community_calls'});
    await tester.pumpAndSettle();
    expect(find.text('Cannot reach the call server.'), findsOneWidget);
    expect(find.text('Join call'), findsNothing);
    expect(find.text('Voice call - 1 joined'), findsNothing);
    api.failure = null;
    api.active = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot reach the call server.'), findsNothing);
    expect(find.text('Voice call'), findsOneWidget);
    await close(tester);
  });

  testWidgets('recording and another call prevent joining', (tester) async {
    api.active = _call(CallKind.voice);
    canCall = false;
    await show(tester);
    await tester.tap(find.text('Join call'));
    await tester.pumpAndSettle();
    expect(prepared, 1);
    expect(calls.joins, isEmpty);
    calls.callState.value = _call(CallKind.video);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await close(tester);
  });

  testWidgets(
      'small screens fit call controls and disconnected fallback refreshes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    api.isLive = false;
    await show(tester);
    final reads = api.reads;
    api.active = _call(CallKind.voice);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(api.reads, greaterThan(reads));
    expect(find.text('Join call'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}
