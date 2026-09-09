import 'dart:async';

import 'package:fast_travel/models/models.dart';
import 'package:fast_travel/screens/chat/chat_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

RoomMessage _message(String id, String time, {String? text}) => RoomMessage(
      id: id,
      senderId: 'traveller',
      senderName: 'Traveller',
      type: 'text',
      text: text ?? id,
      createdAt: time,
    );

void main() {
  test('merging a refresh keeps history and a racing send exactly once', () {
    final older = _message('old', '2026-09-01T10:00:00Z');
    final recent = _message('recent', '2026-09-02T10:00:00Z');
    final sent = _message('sent', '2026-09-03T10:00:00Z');
    final updated = _message('recent', recent.createdAt, text: 'Updated');
    List<RoomMessage> merge(
            List<RoomMessage> current, List<RoomMessage> incoming) =>
        mergeChatMessages(current, incoming,
            id: (message) => message.id,
            createdAt: (message) => message.createdAt);
    final refresh = merge([older, recent, sent], [updated, sent]);
    final acknowledged = merge(refresh, [sent]);
    expect(
        acknowledged.map((message) => message.id), ['old', 'recent', 'sent']);
    expect(acknowledged[1].text, 'Updated');
    expect(merge(acknowledged, [updated]).last.id, 'sent');
  });

  test('same-time messages have stable ordering across refreshes', () {
    final merged = mergeChatMessages(
      [_message('b', '2026-09-01T10:00:00Z')],
      [_message('a', '2026-09-01T10:00:00Z')],
      id: (message) => message.id,
      createdAt: (message) => message.createdAt,
    );
    expect(merged.map((message) => message.id), ['b', 'a']);
  });

  test('sender runs break at midnight and after five minutes', () {
    expect(sameChatRun('2026-09-01T23:59:00', '2026-09-02T00:01:00'), isFalse);
    expect(sameChatRun('2026-09-01T10:00:00', '2026-09-01T10:04:59'), isTrue);
    expect(sameChatRun('2026-09-01T10:00:00', '2026-09-01T10:05:00'), isFalse);
    expect(startsChatDay(null, 'invalid'), isFalse);
    expect(startsChatDay(null, '2026-09-01T10:00:00'), isTrue);
  });

  testWidgets('date chips localize today and yesterday', (tester) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('en'), Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: Column(children: [
          ChatDateSeparator(timestamp: now.toIso8601String()),
          ChatDateSeparator(timestamp: yesterday.toIso8601String()),
          const ChatDateSeparator(timestamp: 'invalid'),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Aujourd'hui"), findsOneWidget);
    expect(find.text('Hier'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry needs explicit confirmation and warns about duplicates',
      (tester) async {
    var sends = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ChatNotice(
            message: 'Send not confirmed. Your draft is kept.',
            onRetry: () async {
              if (await confirmChatRetry(context)) sends++;
            },
          ),
        ),
      ),
    ));
    expect(sends, 0);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('twice'), findsOneWidget);
    expect(sends, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sends, 0);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send again'));
    await tester.pumpAndSettle();
    expect(sends, 1);
  });

  testWidgets('realtime events coalesce without overlapping refreshes',
      (tester) async {
    final changes = StreamController<Set<String>>.broadcast(sync: true);
    final first = Completer<void>();
    var reads = 0;
    var inFlight = 0;
    var maximum = 0;
    final controller = ChatRefreshController(
      changes: changes.stream,
      topics: const {'chat'},
      isLive: () => true,
      isVisible: () => true,
      invalidate: (_) => fail('Realtime cache re-reads must not invalidate'),
      load: () async {
        reads++;
        inFlight++;
        if (inFlight > maximum) maximum = inFlight;
        if (reads == 1) await first.future;
        inFlight--;
      },
    )..start();
    changes.add({'friends'});
    changes.add({'chat'});
    changes.add({'all'});
    expect(reads, 1);
    first.complete();
    await tester.pump();
    expect(reads, 2);
    expect(maximum, 1);
    await tester.pump(const Duration(seconds: 31));
    expect(reads, 2);
    controller.dispose();
    await changes.close();
  });

  testWidgets('fallback only runs offline and visible, resumes and disposes',
      (tester) async {
    final changes = StreamController<Set<String>>.broadcast(sync: true);
    var visible = true;
    var live = true;
    var reads = 0;
    var invalidations = 0;
    Set<String>? invalidatedTopics;
    final controller = ChatRefreshController(
      changes: changes.stream,
      topics: const {'friends'},
      isLive: () => live,
      isVisible: () => visible,
      load: () async => reads++,
      invalidate: (topics) {
        invalidatedTopics = topics;
        invalidations++;
      },
    )..start();
    controller.visibilityChanged();
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 1);
    expect(invalidations, 0);
    live = false;
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 2);
    expect(invalidations, 1);
    expect(invalidatedTopics, {'friends'});
    visible = false;
    controller.visibilityChanged();
    changes.add({'friends'});
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 2);
    visible = true;
    controller.visibilityChanged();
    await tester.pump();
    expect(reads, 3);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    changes.add({'all'});
    await tester.pump(const Duration(seconds: 60));
    expect(reads, 3);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 4);
    expect(invalidations, 3);
    controller.dispose();
    changes.add({'friends'});
    await tester.pump(const Duration(seconds: 60));
    expect(reads, 4);
    await changes.close();
  });

  testWidgets('manual refresh invalidates once without an event feedback loop',
      (tester) async {
    final changes = StreamController<Set<String>>.broadcast(sync: true);
    var invalidations = 0;
    var reads = 0;
    final controller = ChatRefreshController(
      changes: changes.stream,
      topics: const {'chat'},
      isLive: () => true,
      isVisible: () => true,
      invalidate: (topics) {
        invalidations++;
        changes.add(topics);
      },
      load: () async => reads++,
    )..start();
    await tester.pump();
    await controller.refreshFromNetwork();
    await tester.pump();
    expect(invalidations, 1);
    expect(reads, 3);
    changes.add({'chat'});
    await tester.pump();
    expect(invalidations, 1);
    expect(reads, 4);
    controller.dispose();
    await changes.close();
  });
}
