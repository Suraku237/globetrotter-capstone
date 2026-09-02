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
  final String role;
  final String? avatarUrl;

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.avatarUrl,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        fullName: (json['full_name'] ?? '').toString(),
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

  RegistrationResult({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
  });

  factory RegistrationResult.fromJson(Map<String, dynamic> json) =>
      RegistrationResult(
        id: (json['id'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        fullName: (json['full_name'] ?? '').toString(),
        role: (json['role'] ?? 'user').toString(),
        status: (json['status'] ?? '').toString(),
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

// ---- Direct messaging ----

class ChatUser {
  final String id;
  final String fullName;
  final String? avatarUrl;

  ChatUser({required this.id, required this.fullName, this.avatarUrl});

  factory ChatUser.fromJson(Map<String, dynamic> json) => ChatUser(
        id: json['id'] as String,
        fullName: (json['full_name'] ?? '').toString(),
        avatarUrl: json['avatar_url'] as String?,
      );
}

class ChatMessage {
  final String id;
  final String senderId;
  final String type; // 'text' | 'audio' | 'sticker'
  final String? text;
  final String? sticker;
  final String? audioUrl;
  final String createdAt;
  final List<String> readBy;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.type,
    this.text,
    this.sticker,
    this.audioUrl,
    required this.createdAt,
    required this.readBy,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        type: (json['type'] ?? 'text').toString(),
        text: json['text'] as String?,
        sticker: json['sticker'] as String?,
        audioUrl: json['audio_url'] as String?,
        createdAt: (json['created_at'] ?? '').toString(),
        readBy: List<String>.from(json['read_by'] as List? ?? []),
      );
}

// ---- Public community room: one shared thread everyone can post in ----

class RoomMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String type; // 'text' | 'audio' | 'sticker'
  final String? text;
  final String? sticker;
  final String? audioUrl;
  final String createdAt;

  RoomMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.type,
    this.text,
    this.sticker,
    this.audioUrl,
    required this.createdAt,
  });

  factory RoomMessage.fromJson(Map<String, dynamic> json) => RoomMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        senderName: (json['sender_name'] ?? '').toString(),
        senderAvatar: json['sender_avatar'] as String?,
        type: (json['type'] ?? 'text').toString(),
        text: json['text'] as String?,
        sticker: json['sticker'] as String?,
        audioUrl: json['audio_url'] as String?,
        createdAt: (json['created_at'] ?? '').toString(),
      );
}

class ChatConversation {
  final String id;
  final ChatUser? otherUser;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final String updatedAt;

  ChatConversation({
    required this.id,
    this.otherUser,
    this.lastMessage,
    required this.unreadCount,
    required this.updatedAt,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        id: json['id'] as String,
        otherUser: json['other_user'] != null
            ? ChatUser.fromJson(json['other_user'] as Map<String, dynamic>)
            : null,
        lastMessage: json['last_message'] != null
            ? ChatMessage.fromJson(json['last_message'] as Map<String, dynamic>)
            : null,
        unreadCount: (json['unread_count'] as num? ?? 0).toInt(),
        updatedAt: (json['updated_at'] ?? '').toString(),
      );
}
