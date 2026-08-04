class Destination {
  final String id;
  final String name;
  final String region;
  final List<String> tags;
  final String imageUrl; // Fully-qualified URL served by the data-service
  final String description;
  final double lat;
  final double lng;

  Destination({
    required this.id,
    required this.name,
    required this.region,
    required this.tags,
    required this.imageUrl,
    required this.description,
    required this.lat,
    required this.lng,
  });

  // baseUrl is the API gateway origin (e.g. http://host:8000); destination
  // images are served from there, at whatever relative path the backend
  // returns in `images` (e.g. /images/dest_001.jpg).
  factory Destination.fromJson(Map<String, dynamic> json, {required String baseUrl}) {
    final images = json['images'];
    String imageUrl = '';
    if (images is List && images.isNotEmpty) {
      final first = images.first.toString();
      imageUrl = first.startsWith('http') ? first : '$baseUrl$first';
    }

    return Destination(
      id: json['id'] as String,
      name: json['name'] as String,
      region: json['region'] as String,
      tags: List<String>.from(json['tags'] as List),
      imageUrl: imageUrl,
      description: (json['description'] ?? '').toString(),
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
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

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        fullName: (json['full_name'] ?? '').toString(),
        role: (json['role'] ?? 'user').toString(),
      );
}
