enum CallKind { voice, video }

class CallSession {
  final String id;
  final CallKind kind;
  final String targetType;
  final String targetId;
  final String title;
  final String callerId;
  final String callerName;
  final String? callerAvatarUrl;
  final String status;
  final DateTime expiresAt;
  final List<String> participantIds;
  final List<String> acceptedIds;
  final String? endedReason;

  const CallSession({
    required this.id,
    required this.kind,
    required this.targetType,
    required this.targetId,
    required this.title,
    required this.callerId,
    required this.callerName,
    required this.callerAvatarUrl,
    required this.status,
    required this.expiresAt,
    required this.participantIds,
    required this.acceptedIds,
    required this.endedReason,
  });

  bool get isEnded => status == 'ended';
  bool get isGroup => targetType == 'group';

  bool canAnswer(String userId, DateTime now) =>
      (status == 'ringing' || status == 'active') &&
      expiresAt.isAfter(now) &&
      callerId != userId &&
      participantIds.contains(userId) &&
      !acceptedIds.contains(userId);

  CallSession endedLocally() => CallSession(
        id: id,
        kind: kind,
        targetType: targetType,
        targetId: targetId,
        title: title,
        callerId: callerId,
        callerName: callerName,
        callerAvatarUrl: callerAvatarUrl,
        status: 'ended',
        expiresAt: expiresAt,
        participantIds: participantIds,
        acceptedIds: acceptedIds,
        endedReason: endedReason ?? 'Call ended',
      );

  factory CallSession.fromJson(Map<String, dynamic> json) => CallSession(
        id: json['id'] as String,
        kind: CallKind.values.byName(json['kind'] as String),
        targetType: json['target_type'] as String,
        targetId: json['target_id'] as String,
        title: json['title'] as String,
        callerId: json['caller_id'] as String,
        callerName: json['caller_name'] as String,
        callerAvatarUrl: json['caller_avatar_url'] as String?,
        status: json['status'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        participantIds: List<String>.from(json['participant_ids'] as List),
        acceptedIds: List<String>.from(json['accepted_ids'] as List),
        endedReason: json['ended_reason'] as String?,
      );
}

class CallConnection {
  final CallSession call;
  final String url;
  final String token;

  const CallConnection({
    required this.call,
    required this.url,
    required this.token,
  });

  factory CallConnection.fromJson(Map<String, dynamic> json) => CallConnection(
        call: CallSession.fromJson(json['call'] as Map<String, dynamic>),
        url: json['url'] as String,
        token: json['token'] as String,
      );
}
