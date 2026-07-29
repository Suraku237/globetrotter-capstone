class Destination {
  final String id;
  final String name;
  final String region;
  final List<String> tags;
  final String imageUrl;
  final String description;

  Destination({
    required this.id,
    required this.name,
    required this.region,
    required this.tags,
    required this.imageUrl,
    this.description = '',
  });

  factory Destination.fromJson(Map<String, dynamic> json) => Destination(
        id: json['id'] as String,
        name: json['name'] as String,
        region: json['region'] as String,
        tags: List<String>.from(json['tags'] as List),
        imageUrl: (json['image_url'] ?? json['imageUrl'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
      );
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

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        role: (json['role'] ?? 'user').toString(),
      );
}
