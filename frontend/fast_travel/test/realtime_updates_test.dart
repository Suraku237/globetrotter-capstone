import 'dart:async';
import 'dart:convert';

import 'package:fast_travel/Services/realtime_updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Sink extends Fake implements WebSocketSink {
  final sent = <dynamic>[];
  bool closed = false;
  @override
  void add(dynamic data) => sent.add(data);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }
}

class _Channel extends Fake implements WebSocketChannel {
  final server = StreamController<dynamic>();
  final output = _Sink();
  int? code;
  @override
  Future<void> get ready => Future.value();
  @override
  Stream<dynamic> get stream => server.stream;
  @override
  WebSocketSink get sink => output;
  @override
  int? get closeCode => code;
}

void main() {
  late RealtimeUpdates live;
  late List<_Channel> channels;
  late List<Set<String>> events;
  late int unauthorized;
  late DateTime now;
  setUp(() {
    channels = [];
    events = [];
    unauthorized = 0;
    now = DateTime.utc(2026, 9, 9);
    live = RealtimeUpdates(
      uri: Uri.parse('wss://example.test/api/events/ws'),
      onInvalidate: events.add,
      onUnauthorized: () => unauthorized++,
      now: () => now,
      connect: (uri) {
        expectSync(uri.query, isEmpty);
        final channel = _Channel();
        channels.add(channel);
        return channel;
      },
    );
  });

  testWidgets('authenticates in first frame and resyncs only after ready',
      (tester) async {
    live.setToken('private-token');
    await tester.pump();
    expect(jsonDecode(channels.single.output.sent.single as String),
        {'token': 'private-token'});
    expect(live.connected.value, isFalse);
    channels.single.server.add('{"type":"ready","topics":["all"]}');
    await tester.pump();
    expect(live.connected.value, isTrue);
    expect(events, [
      equals({'all'})
    ]);
    channels.single.server
        .add('{"type":"invalidate","topics":["friends","calls"]}');
    await tester.pump();
    expect(events.last, {'friends', 'calls'});
    live.dispose();
  });

  testWidgets('reconnects with resync after connection loss', (tester) async {
    live.setToken('token');
    await tester.pump();
    channels.first.server.add('{"type":"ready"}');
    await tester.pump();
    unawaited(channels.first.server.close());
    await tester.pump();
    expect(live.connected.value, isFalse);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(channels.length, 2);
    channels.last.server.add('{"type":"ready"}');
    await tester.pump();
    expect(events, [
      equals({'all'}),
      equals({'all'})
    ]);
    live.dispose();
  });

  testWidgets('logout cancels reconnect and ignores old socket messages',
      (tester) async {
    live.setToken('alice');
    await tester.pump();
    live.setToken(null);
    channels.first.server.add('{"type":"invalidate","topics":["friends"]}');
    await tester.pump(const Duration(minutes: 1));
    expect(events, isEmpty);
    expect(channels.length, 1);
    expect(channels.first.output.closed, isTrue);
    live.dispose();
  });

  testWidgets('background stops connection and resume resynchronizes',
      (tester) async {
    live.setToken('token');
    await tester.pump();
    live.setActive(false);
    await tester.pump(const Duration(minutes: 1));
    expect(channels.length, 1);
    live.setActive(true);
    await tester.pump();
    expect(channels.length, 2);
    channels.last.server.add('{"type":"ready"}');
    await tester.pump();
    expect(events.single, {'all'});
    live.dispose();
  });

  testWidgets('expired authentication is surfaced without retry loop',
      (tester) async {
    live.setToken('expired');
    await tester.pump();
    channels.first.code = 4401;
    unawaited(channels.first.server.close());
    await tester.pump(const Duration(minutes: 1));
    expect(unauthorized, 1);
    expect(live.connected.value, isFalse);
    expect(channels.length, 1);
    live.dispose();
  });

  testWidgets('silent connection is dropped by watchdog', (tester) async {
    live.setToken('token');
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(channels.single.output.sent, contains('{"type":"ping"}'));
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 15));
    expect(channels.first.output.closed, isTrue);
    expect(live.connected.value, isFalse);
    live.dispose();
  });
}
