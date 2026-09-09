import 'package:fast_travel/models/call_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> callJson({
  String status = 'ringing',
  String kind = 'voice',
  String targetType = 'direct',
  List<String> accepted = const ['alice'],
}) =>
    {
      'id': 'call-id',
      'kind': kind,
      'target_type': targetType,
      'target_id': 'bob',
      'title': 'Bob',
      'caller_id': 'alice',
      'caller_name': 'Alice',
      'caller_avatar_url': null,
      'status': status,
      'expires_at': '2026-09-07T12:01:00Z',
      'participant_ids': ['alice', 'bob', 'charlie'],
      'accepted_ids': accepted,
      'ended_reason': status == 'ended' ? 'declined' : null,
    };

void main() {
  final beforeExpiry = DateTime.utc(2026, 9, 7, 12);
  final expiry = DateTime.utc(2026, 9, 7, 12, 1);

  test('voice and video connection responses retain server room credentials',
      () {
    for (final kind in CallKind.values) {
      final connection = CallConnection.fromJson({
        'call': callJson(kind: kind.name),
        'url': 'wss://example.livekit.cloud',
        'token': 'test-token',
      });
      expect(connection.call.kind, kind);
      expect(connection.url, 'wss://example.livekit.cloud');
      expect(connection.token, 'test-token');
    }
  });

  test('only an invited, unaccepted participant can answer', () {
    final call = CallSession.fromJson(callJson());
    expect(call.canAnswer('bob', beforeExpiry), isTrue);
    expect(call.canAnswer('alice', beforeExpiry), isFalse);
    expect(call.canAnswer('outsider', beforeExpiry), isFalse);
    final accepted = CallSession.fromJson(callJson(accepted: ['alice', 'bob']));
    expect(accepted.canAnswer('bob', beforeExpiry), isFalse);
  });

  test('expired, ended and unknown calls cannot be answered', () {
    final call = CallSession.fromJson(callJson());
    expect(call.canAnswer('bob', expiry), isFalse);
    expect(
        call.canAnswer('bob', expiry.add(const Duration(seconds: 1))), isFalse);
    for (final status in ['ended', 'unknown']) {
      expect(
        CallSession.fromJson(callJson(status: status))
            .canAnswer('bob', beforeExpiry),
        isFalse,
      );
    }
  });

  test('group invite remains answerable when another member already joined',
      () {
    final call = CallSession.fromJson(callJson(
      status: 'active',
      targetType: 'group',
      accepted: ['alice', 'bob'],
    ));
    expect(call.isGroup, isTrue);
    expect(call.canAnswer('charlie', beforeExpiry), isTrue);
    expect(call.canAnswer('bob', beforeExpiry), isFalse);
  });

  test('leaving locally ends only this view and preserves server session', () {
    final original = CallSession.fromJson(callJson(status: 'active'));
    final ended = original.endedLocally();
    expect(original.status, 'active');
    expect(ended.isEnded, isTrue);
    expect(ended.endedReason, 'Call ended');
    expect(ended.id, original.id);
    expect(ended.participantIds, original.participantIds);
    expect(ended.canAnswer('bob', beforeExpiry), isFalse);
    final declined = CallSession.fromJson(callJson(status: 'ended'));
    expect(declined.endedLocally().endedReason, 'declined');
  });

  test('community is multiuser but never an incoming ringing invitation', () {
    for (final status in ['active', 'ringing']) {
      final call = CallSession.fromJson(
          callJson(status: status, targetType: 'community'));
      expect(call.isGroup, isTrue);
      expect(call.isCommunity, isTrue);
      expect(call.canAnswer('bob', beforeExpiry), isFalse);
      expect(call.canAnswer('outsider', beforeExpiry), isFalse);
    }
  });

  test('invalid call kinds are rejected rather than treated as voice', () {
    expect(() => CallSession.fromJson(callJson(kind: 'invalid')),
        throwsArgumentError);
  });
}
