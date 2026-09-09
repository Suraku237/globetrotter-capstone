import 'dart:async';
import 'dart:convert';

import 'package:fast_travel/Services/api_service.dart';
import 'package:fast_travel/Services/call_coordinator.dart';
import 'package:fast_travel/Services/session_state.dart';
import 'package:fast_travel/models/models.dart';
import 'package:fast_travel/screens/chat/community_room_screen.dart';
import 'package:fast_travel/screens/friends/friends_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends Fake implements SessionState {
  @override
  final currentUser = AppUser(
      id: 'me',
      email: 'me@example.com',
      fullName: 'Me',
      username: 'me',
      role: 'user');
}

Map<String, dynamic> _message(int index,
        {String? text, String sender = 'friend'}) =>
    {
      'id': 'message-$index',
      'sender_id': sender,
      'sender_name': sender == 'me' ? 'Me' : 'Friend',
      'type': 'text',
      'text': text ?? 'Message $index',
      'created_at': DateTime(2026, 9, 1, 10, index).toIso8601String(),
    };

http.Response _json(Object data, {int status = 200}) =>
    http.Response(jsonEncode(data), status,
        headers: {'content-type': 'application/json'});

Future<void> _flushNetwork(WidgetTester tester) async {
  // The singleton HTTP client is created outside the widget's fake-async zone.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<void> _settle(WidgetTester tester) async {
  await _flushNetwork(tester);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = _Session();
  late Future<http.Response> Function(http.Request) respond;
  late ApiService api;
  final client = MockClient((request) => respond(request));

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    api = http.runWithClient(() => ApiService.instance, () => client);
    CallCoordinator.instance = CallCoordinator(
      session: session,
      navigatorKey: GlobalKey<NavigatorState>(),
      messengerKey: GlobalKey<ScaffoldMessengerState>(),
    );
  });

  for (final label in ['community', 'private', 'group']) {
    final community = label == 'community';
    Widget screen() => MaterialApp(
          home: community
              ? CommunityRoomScreen(session: session)
              : label == 'private'
                ? ConversationScreen.direct(
                  session: session,
                  friend: const SocialUser(
                      id: 'friend', fullName: 'Friend', username: 'friend'),
                )
                : ConversationScreen.group(
                    session: session,
                    group: const ChatGroup(
                      id: 'group',
                      name: 'Travel friends',
                      ownerId: 'me',
                      members: [
                        SocialUser(id: 'friend', fullName: 'Friend', username: 'friend'),
                      ],
                      createdAt: '2026-09-01T10:00:00',
                    ),
                  ),
        );

    testWidgets('$label older pages keep their exclusive cursor with timestamp ties',
        (tester) async {
      final cursors = <String>[];
      respond = (request) async {
        if (!request.url.path.endsWith('/messages')) {
          return _json({'count': 0, 'users': []});
        }
        expectSync(request.url.queryParameters['limit'], '50');
        final cursor = request.url.queryParameters['before'];
        if (cursor != null) cursors.add(cursor);
        return _json([
          for (var i = cursor == null ? 10 : 0; i < (cursor == null ? 60 : 10); i++)
            {..._message(i), 'created_at': '2026-09-01T10:00:00Z'},
        ]);
      };
      await tester.pumpWidget(screen());
      await _settle(tester);
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load older messages'));
      await _settle(tester);
      expect(cursors, ['message-10']);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('Message 0'), findsOneWidget);
      api.refreshTopics({community ? 'chat' : 'friends'});
      await _settle(tester);
      expect(find.text('Message 0'), findsOneWidget);
      expect(find.text('Load older messages'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    });

    testWidgets('$label keeps draft after failure and never retries on its own',
        (tester) async {
      var sends = 0;
      var reads = 0;
      respond = (request) async {
        if (request.url.path.endsWith('/messages')) {
          if (request.method == 'POST') {
            sends++;
            return _json({'detail': 'Connection interrupted'}, status: 503);
          }
          reads++;
          return _json([_message(1)]);
        }
        return _json({'count': 0, 'users': []});
      };
      await tester.pumpWidget(screen());
      await _settle(tester);
      expect(reads, greaterThan(0), reason: 'The initial read should reach the mock client');
      expect(find.text('Message 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await _settle(tester);
      expect(sends, 1);
      expect(find.textContaining('Send not confirmed.'), findsOneWidget);
      final composer = tester.widget<TextField>(find.byType(TextField));
      expect(composer.controller!.text, 'Keep this draft');
      await tester.pump(const Duration(seconds: 31));
      await _settle(tester);
      expect(sends, 1);
      expect(composer.controller!.text, 'Keep this draft');
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label merges refresh racing send and preserves new typing',
        (tester) async {
      final sent = _message(2, text: 'First draft', sender: 'me');
      final response = Completer<http.Response>();
      var remoteReceived = false;
      respond = (request) async {
        if (request.url.path.endsWith('/messages')) {
          if (request.method == 'POST') return response.future;
          return _json([_message(1), if (remoteReceived) sent]);
        }
        return _json({'count': 0, 'users': []});
      };
      await tester.pumpWidget(screen());
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'First draft');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Next draft');
      remoteReceived = true;
      api.refreshTopics({community ? 'chat' : 'friends'});
      await _flushNetwork(tester);
      await tester.pump(const Duration(milliseconds: 300));
      response.complete(_json(sent, status: 201));
      await _settle(tester);
      expect(find.byKey(const ValueKey('message-2')), findsOneWidget);
      expect(find.text('First draft'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Next draft');
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$label incoming messages do not move a reader away from history',
        (tester) async {
      var received = false;
      respond = (request) async {
        if (request.url.path.endsWith('/messages')) {
          return _json([
            for (var i = 0; i < 50; i++) _message(i),
            if (received) _message(50),
          ]);
        }
        return _json({'count': 0, 'users': []});
      };
      await tester.pumpWidget(screen());
      await _settle(tester);
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      received = true;
      api.refreshTopics({community ? 'chat' : 'friends'});
      await _settle(tester);
      expect(scroll.offset, 0);
      expect(find.text('New messages'), findsOneWidget);
      await tester.tap(find.text('New messages'));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(100));
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'community pagination uses oldest ID and keeps history on refresh',
      (tester) async {
    final cursors = <String>[];
    respond = (request) async {
      if (request.url.path.endsWith('/messages')) {
        final before = request.url.queryParameters['before'];
        if (before != null) cursors.add(before);
        return _json(before == null
            ? [for (var i = 10; i < 60; i++) _message(i)]
            : [for (var i = 0; i < 10; i++) _message(i)]);
      }
      return _json({'count': 0, 'users': []});
    };
    await tester
        .pumpWidget(MaterialApp(home: CommunityRoomScreen(session: session)));
    await _settle(tester);
    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load older messages'));
    await _settle(tester);
    expect(cursors, ['message-10']);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Beginning of the conversation'), findsOneWidget);
    expect(find.text('Message 0'), findsOneWidget);
    api.refreshTopics({'chat'});
    await _settle(tester);
    expect(find.text('Message 0'), findsOneWidget);
    expect(find.text('Load older messages'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('friend requests arrive live and approval updates without a spinner',
      (tester) async {
    var arrived = false;
    var accepted = false;
    var approvals = 0;
    final approval = Completer<http.Response>();
    const friend = {
      'id': 'friend', 'full_name': 'New friend', 'username': 'new_friend',
    };
    respond = (request) async {
      if (request.url.path.endsWith('/accept')) {
        approvals++;
        return approval.future;
      }
      if (request.url.path.endsWith('/friends')) {
        return _json({
          'friends': [if (accepted) friend],
          'incoming_requests': [
            if (arrived && !accepted)
              {'request_id': 'request-1', 'user': friend, 'created_at': ''},
          ],
          'outgoing_requests': [],
        });
      }
      return _json([]);
    };
    await tester.pumpWidget(MaterialApp(home: FriendsScreen(session: session)));
    await _settle(tester);
    expect(find.text('Connect with friends'), findsOneWidget);
    arrived = true;
    api.refreshTopics({'friends'});
    await _settle(tester);
    expect(find.text('Requests (1)'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Requests (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Accept'));
    await _flushNetwork(tester);
    expect(approvals, 1);
    expect(find.byTooltip('Accept'), findsNothing);
    expect(find.text('New friend'), findsOneWidget);
    approval.complete(_json({'ok': true}));
    await _settle(tester);
    expect(find.text('No friend requests'), findsOneWidget);
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(find.text('New friend'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    accepted = true;
    api.refreshTopics({'friends'});
    await _settle(tester);
    expect(find.text('New friend'), findsOneWidget);
    expect(find.text('Requests (1)'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}
