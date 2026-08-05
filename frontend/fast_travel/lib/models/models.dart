class Destination {
  final String id;
  final String name;
  final String region;
  final List<String> tags;
  final String imageAsset; // Single string for local asset path
  final String description;
  final double lat;
  final double lng;
  final String status; // 'approved' | 'pending' | 'rejected'
  final String? imageUrl; // Backend-served path (e.g. /images/dest_x.jpg),
  // only populated for pending-review flows — the rest of the app renders
  // via [imageAsset] (bundled local assets).

  Destination({
    required this.id,
    required this.name,
    required this.region,
    required this.tags,
    required this.imageAsset,
    required this.description,
    required this.lat,
    required this.lng,
    this.status = 'approved',
    this.imageUrl,
  });

  factory Destination.fromJson(Map<String, dynamic> json) {
    String nameSlug = (json['name'] as String)
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll("'", '')
        .replaceAll('-', '_')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('î', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('û', 'u')
        .replaceAll('ç', 'c')
        .replaceAll('á', 'a')
        .replaceAll(' ', '_');

    String assetPath = 'assets/images/$nameSlug.jpg';

    return Destination(
      id: json['id'] as String,
      name: json['name'] as String,
      region: json['region'] as String,
      tags: List<String>.from(json['tags'] as List),
      imageAsset: assetPath,
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
        createdAt: (json['created_at'] ?? '').toString(),
        likes: List<String>.from(json['likes'] as List? ?? []),
        comments: (json['comments'] as List? ?? [])
            .map((c) => Comment.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}
