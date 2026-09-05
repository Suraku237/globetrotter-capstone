class Destination {
  final String id;
  final String name;
  final String region;
  final List<String> tags;
  final String description;
  final double lat;
  final double lng;
  final String status; // 'approved' | 'pending' | 'rejected'
  // Backend-served path (e.g. /images/dest_001.jpg) — resolve with
  // ApiService.resolveUrl before passing to Image.network.
  final String? imageUrl;

  Destination({
    required this.id,
    required this.name,
    required this.region,
    required this.tags,
    required this.description,
    required this.lat,
    required this.lng,
    this.status = 'approved',
    this.imageUrl,
  });

  // There's no backend rating system yet — this derives a stable "good to
  // great" rating (3.5–5.0, in steps of 0.1) from the destination's own id,
  // so every screen that shows a destination shows the same star rating
  // for it instead of a random one changing on every rebuild.
  double get rating => 3.5 + (id.hashCode.abs() % 16) / 10.0;

  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: json['id'] as String,
      name: json['name'] as String,
      region: json['region'] as String,
      tags: List<String>.from(json['tags'] as List),
      description: (json['description'] ?? '').toString(),
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      status: (json['status'] ?? 'approved').toString(),
      imageUrl: (json['images'] is List && (json['images'] as List).isNotEmpty)
          ? (json['images'] as List).first.toString()
          : null,
    );
  }
}

class Itinerary {
  final String id;
  final String title;
  final String destinationId;
  final String startDate;
  final String endDate;
  final String? notes;

  Itinerary({
    required this.id,
    required this.title,
    required this.destinationId,
    required this.startDate,
    required this.endDate,
    this.notes,
  });

  factory Itinerary.fromJson(Map<String, dynamic> json) => Itinerary(
        id: json['id'] as String,
        title: json['title'] as String,
        destinationId: json['destination_id'] as String,
        startDate: json['start_date'] as String,
        endDate: json['end_date'] as String,
        notes: json['notes'] as String?,
      );
}

class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String username;
  final String role;
  final String? avatarUrl;

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.username,
    required this.role,
    this.avatarUrl,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        fullName: (json['full_name'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
        role: (json['role'] ?? 'user').toString(),
        avatarUrl: json['avatar_url'] as String?,
      );
}

// What POST /register actually returns now — registering no longer signs
// you in immediately. [status] tells the caller what to show next:
// 'pending_verification' (enter the emailed code) or
// 'pending_admin_approval' (wait for SUPER_ADMIN_EMAIL to approve).
class RegistrationResult {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String status;
  // Short-lived token the client uses to poll /admin-requests/status
  // while sitting on the "waiting for approval" screen. Only present when
  // [status] is 'pending_admin_approval'.
  final String? pendingSessionToken;

  RegistrationResult({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.pendingSessionToken,
  });

  factory RegistrationResult.fromJson(Map<String, dynamic> json) =>
      RegistrationResult(
        id: (json['id'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        fullName: (json['full_name'] ?? '').toString(),
        role: (json['role'] ?? 'user').toString(),
        status: (json['status'] ?? '').toString(),
        pendingSessionToken: json['pending_session_token'] as String?,
      );
}

// One poll of /admin-requests/status while an admin/worker signup is
// waiting for the super admin to click approve/reject.
enum PendingAdminStatusValue { pending, approved, rejected }

class PendingAdminStatus {
  final PendingAdminStatusValue status;
  // Populated only when [status] is approved — the freshly minted access
  // token and the user record are used to sign the applicant straight in.
  final String? accessToken;
  final AppUser? user;

  const PendingAdminStatus({
    required this.status,
    this.accessToken,
    this.user,
  });

  factory PendingAdminStatus.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? '').toString();
    switch (rawStatus) {
      case 'approved':
        return PendingAdminStatus(
          status: PendingAdminStatusValue.approved,
          accessToken: json['access_token'] as String?,
          user: AppUser.fromJson({
            'id': json['user_id'],
            'email': json['email'],
            'full_name': json['full_name'],
            'username': json['username'],
            'role': json['role'],
            'avatar_url': json['avatar_url'],
          }),
        );
      case 'rejected':
        return const PendingAdminStatus(
          status: PendingAdminStatusValue.rejected,
        );
      case 'pending':
      default:
        return const PendingAdminStatus(
          status: PendingAdminStatusValue.pending,
        );
    }
  }
}

class SocialUser {
  final String id;
  final String fullName;
  final String username;
  final String? avatarUrl;

  const SocialUser({
    required this.id,
    required this.fullName,
    required this.username,
    this.avatarUrl,
  });

  factory SocialUser.fromJson(Map<String, dynamic> json) => SocialUser(
        id: (json['id'] ?? '').toString(),
        fullName: (json['full_name'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
        avatarUrl: json['avatar_url'] as String?,
      );
}

class FriendRequest {
  final String requestId;
  final SocialUser user;
  final String createdAt;

  const FriendRequest({
    required this.requestId,
    required this.user,
    required this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
        requestId: (json['request_id'] ?? '').toString(),
        user: SocialUser.fromJson(json['user'] as Map<String, dynamic>),
        createdAt: (json['created_at'] ?? '').toString(),
      );
}

class FriendsOverview {
  final List<SocialUser> friends;
  final List<FriendRequest> incomingRequests;
  final List<FriendRequest> outgoingRequests;

  const FriendsOverview({
    required this.friends,
    required this.incomingRequests,
    required this.outgoingRequests,
  });

  factory FriendsOverview.fromJson(Map<String, dynamic> json) => FriendsOverview(
        friends: (json['friends'] as List? ?? [])
            .map((item) => SocialUser.fromJson(item as Map<String, dynamic>))
            .toList(),
        incomingRequests: (json['incoming_requests'] as List? ?? [])
            .map((item) => FriendRequest.fromJson(item as Map<String, dynamic>))
            .toList(),
        outgoingRequests: (json['outgoing_requests'] as List? ?? [])
            .map((item) => FriendRequest.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class SocialMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final String createdAt;

  const SocialMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  factory SocialMessage.fromJson(Map<String, dynamic> json) => SocialMessage(
        id: (json['id'] ?? '').toString(),
        senderId: (json['sender_id'] ?? '').toString(),
        senderName: (json['sender_name'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
      );
}

class ChatGroup {
  final String id;
  final String name;
  final String ownerId;
  final List<SocialUser> members;
  final String createdAt;

  const ChatGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.members,
    required this.createdAt,
  });

  factory ChatGroup.fromJson(Map<String, dynamic> json) => ChatGroup(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        ownerId: (json['owner_id'] ?? '').toString(),
        members: (json['members'] as List? ?? [])
            .map((item) => SocialUser.fromJson(item as Map<String, dynamic>))
            .toList(),
        createdAt: (json['created_at'] ?? '').toString(),
      );
}

class Comment {
  final String id;
  final String userId;
  final String authorName;
  final String text;
  final String createdAt;

  Comment({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        authorName: (json['author_name'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
      );
}

class Post {
  final String id;
  final String userId;
  final String authorName;
  final String? authorAvatar;
  final String text;
  final String? image;
  final String? video;
  final String createdAt;
  final List<String> likes;
  final List<Comment> comments;

  Post({
    required this.id,
    required this.userId,
    required this.authorName,
    this.authorAvatar,
    required this.text,
    this.image,
    this.video,
    required this.createdAt,
    required this.likes,
    required this.comments,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        authorName: (json['author_name'] ?? '').toString(),
        authorAvatar: json['author_avatar'] as String?,
        text: (json['text'] ?? '').toString(),
        image: json['image'] as String?,
        video: json['video'] as String?,
        createdAt: (json['created_at'] ?? '').toString(),
        likes: List<String>.from(json['likes'] as List? ?? []),
        comments: (json['comments'] as List? ?? [])
            .map((c) => Comment.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

// ---- Public community room: one shared thread everyone can post in ----

class RoomReplyPreview {
  final String id;
  final String? senderId;
  final String? senderName;
  final String excerpt;

  const RoomReplyPreview({
    required this.id,
    this.senderId,
    this.senderName,
    required this.excerpt,
  });

  factory RoomReplyPreview.fromJson(Map<String, dynamic> json) =>
      RoomReplyPreview(
        id: json['id'] as String,
        senderId: json['sender_id'] as String?,
        senderName: json['sender_name'] as String?,
        excerpt: (json['excerpt'] ?? '').toString(),
      );
}

class RoomMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  // 'text' | 'audio' | 'sticker' | 'image' — a soft-deleted message
  // keeps its original type but has `deleted == true`, so the UI can
  // still render it in the correct row style (own vs other) while
  // showing a tombstone instead of the content.
  final String type;
  final String? text;
  final String? sticker;
  final String? audioUrl;
  final String? imageUrl;
  final String createdAt;
  final RoomReplyPreview? replyTo;
  // emoji -> list of user ids who reacted with it. Keeps the JSON round
  // trip cheap; the UI aggregates counts on the client.
  final Map<String, List<String>> reactions;
  final bool deleted;

  RoomMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.type,
    this.text,
    this.sticker,
    this.audioUrl,
    this.imageUrl,
    required this.createdAt,
    this.replyTo,
    this.reactions = const {},
    this.deleted = false,
  });

  factory RoomMessage.fromJson(Map<String, dynamic> json) {
    final rawReactions = json['reactions'];
    final reactions = <String, List<String>>{};
    if (rawReactions is Map) {
      rawReactions.forEach((key, value) {
        if (value is List) {
          reactions[key.toString()] =
              value.map((v) => v.toString()).toList(growable: false);
        }
      });
    }
    return RoomMessage(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      senderName: (json['sender_name'] ?? '').toString(),
      senderAvatar: json['sender_avatar'] as String?,
      type: (json['type'] ?? 'text').toString(),
      text: json['text'] as String?,
      sticker: json['sticker'] as String?,
      audioUrl: json['audio_url'] as String?,
      imageUrl: json['image_url'] as String?,
      createdAt: (json['created_at'] ?? '').toString(),
      replyTo: json['reply_to'] is Map<String, dynamic>
          ? RoomReplyPreview.fromJson(json['reply_to'] as Map<String, dynamic>)
          : null,
      reactions: reactions,
      deleted: json['deleted'] as bool? ?? false,
    );
  }
}

class RoomActiveUser {
  final String id;
  final String fullName;
  final String? avatarUrl;

  const RoomActiveUser({
    required this.id,
    required this.fullName,
    this.avatarUrl,
  });

  factory RoomActiveUser.fromJson(Map<String, dynamic> json) => RoomActiveUser(
        id: json['id'] as String,
        fullName: (json['full_name'] ?? '').toString(),
        avatarUrl: json['avatar_url'] as String?,
      );
}

class RoomPresence {
  final int count;
  final List<RoomActiveUser> users;

  const RoomPresence({required this.count, required this.users});

  factory RoomPresence.fromJson(Map<String, dynamic> json) => RoomPresence(
        count: (json['count'] as num? ?? 0).toInt(),
        users: (json['users'] as List? ?? [])
            .map((u) => RoomActiveUser.fromJson(u as Map<String, dynamic>))
            .toList(),
      );
}
