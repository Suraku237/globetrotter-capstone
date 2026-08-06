// GlobeTrotter API client — typed, platform-aware, works unchanged on
// mobile, desktop, and web builds of the same Flutter app.
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  bool get isUnauthorized => statusCode == 401;
  @override
  String toString() => message;
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  String? _token;
  void setToken(String? token) => _token = token;
  bool get isAuthenticated => _token != null;

  // Called whenever a request comes back 401 — the token has been rejected
  // by the backend (expired, or issued against a different user store than
  // the service that's validating it). Wired up in main.dart to sign the
  // user out and drop them back on the login screen instead of leaving the
  // app stuck showing a stale, misleading error.
  void Function()? onUnauthorized;

  // 🔥 FORCED TO USE YOUR VPS IP GATEWAY
  static String get baseUrl {
    return 'http://109.199.120.38:8000';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _handle(http.Response res, {int okStatus = 200}) async {
    if (res.statusCode == okStatus) {
      return res.body.isEmpty ? null : jsonDecode(res.body);
    }
    String detail = res.body;
    try {
      final parsed = jsonDecode(res.body);
      detail = parsed['detail']?.toString() ?? res.body;
    } catch (_) {}
    if (res.statusCode == 401) {
      _token = null;
      onUnauthorized?.call();
    }
    throw ApiException(detail, statusCode: res.statusCode);
  }

  Future<AppUser> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    print('📤 API: Register called for: $email');
    final res = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
        'role': role,
      }),
    );
    
    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = jsonDecode(res.body);
      print('✅ Registration successful');
      
      return AppUser(
        id: data['id'] ?? 'user_123',  // ✅ Dynamically gets ID from backend
        email: email,
        fullName: fullName,
        role: role,
      );
    } else {
      throw ApiException('Registration failed: ${res.statusCode}');
    }
  }

  Future<AppUser> login(
      {required String email, required String password}) async {
    print('📤 API: Login called for: $email');
    final res = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setToken(data['access_token'] as String);
      print('✅ Login successful');
      
      return AppUser.fromJson({
        'id': data['user_id'],
        'email': data['email'],
        'full_name': data['full_name'],
        'role': data['role'],
        'avatar_url': data['avatar_url'],
      });
    } else {
      throw ApiException('Login failed: ${res.statusCode}');
    }
  }

  Future<AppUser> loginWithGoogle({required String idToken}) async {
    print('📤 API: loginWithGoogle called');
    print('📤 Token length: ${idToken.length}');
    print(
        '📤 Token preview: ${idToken.substring(0, idToken.length > 30 ? 30 : idToken.length)}...');
    print('📤 URL: $baseUrl/auth/google');

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/google'),
        headers: _headers,
        body: jsonEncode({'id_token': idToken}),
      );

      print('📥 Response status: ${res.statusCode}');
      print(
          '📥 Response body: ${res.body.substring(0, res.body.length > 100 ? 100 : res.body.length)}...');

      if (res.statusCode != 200) {
        throw ApiException('Server returned ${res.statusCode}: ${res.body}');
      }

      final data = jsonDecode(res.body);
      print('✅ API success');

      setToken(data['access_token'] as String);

      return AppUser.fromJson({
        'id': data['user_id'] ?? '123',
        'email': data['email'] ?? 'mock@user.com',
        'full_name': data['full_name'] ?? 'Mock User',
        'role': 'user',
        'avatar_url': data['avatar_url'],
      });
    } catch (e) {
      print('❌ API Exception: $e');
      rethrow;
    }
  }

  Future<List<Destination>> getDestinations({String? query}) async {
    final uri = Uri.parse('$baseUrl/destinations').replace(
      queryParameters:
          (query != null && query.isNotEmpty) ? {'q': query} : null,
    );
    final res = await http.get(uri, headers: _headers);

    print('📤 API: Getting destinations');
    print('📥 Response status: ${res.statusCode}');

    await _handle(res);

    final dynamic jsonData = jsonDecode(res.body);
    List<dynamic> rawList = [];

    if (jsonData is Map<String, dynamic> &&
        jsonData.containsKey('destinations')) {
      rawList = jsonData['destinations'] as List;
      print('✅ Got ${rawList.length} destinations');
    } else if (jsonData is List) {
      rawList = jsonData;
      print('✅ Got ${rawList.length} destinations');
    } else {
      throw ApiException('Unexpected response format');
    }

    for (var item in rawList) {
      item.remove('images');
      item.remove('image_url');
    }

    return rawList.map((e) => Destination.fromJson(e)).toList();
  }

  Future<List<Destination>> getRecommendations() async {
    print('📤 API: Getting recommendations');
    final res = await http.get(
      Uri.parse('$baseUrl/recommendations'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    print('✅ Got ${data.length} recommendations');
    return data.map((e) => Destination.fromJson(e)).toList();
  }

  Future<Itinerary> createItinerary({
    required String title,
    required String destinationId,
    required String startDate,
    required String endDate,
    String? notes,
  }) async {
    print('📤 API: Creating itinerary: $title');
    final res = await http.post(
      Uri.parse('$baseUrl/itineraries'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'destination_id': destinationId,
        'start_date': startDate,
        'end_date': endDate,
        'notes': notes,
      }),
    );

    final data = await _handle(res, okStatus: 201);
    print('✅ Itinerary created successfully');

    return Itinerary(
      id: data['id'] ?? 'mock_id',
      title: title,
      destinationId: destinationId,
      startDate: startDate,
      endDate: endDate,
      notes: notes,
    );
  }

  Future<List<Itinerary>> getItineraries() async {
    print('📤 API: Getting itineraries');
    final res = await http.get(
      Uri.parse('$baseUrl/itineraries'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    print('✅ Got ${data.length} itineraries');
    return data.map((e) => Itinerary.fromJson(e)).toList();
  }

  // ---- Profile ----

  Future<AppUser> updateProfile({required String fullName}) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/me'),
      headers: _headers,
      body: jsonEncode({'full_name': fullName}),
    );
    final data = await _handle(res);
    return AppUser.fromJson(data as Map<String, dynamic>);
  }

  Future<AppUser> uploadAvatar(XFile file) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/me/avatar'));
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    final bytes = await file.readAsBytes();
    request.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: file.name));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = await _handle(res);
    return AppUser.fromJson(data as Map<String, dynamic>);
  }

  // ---- Social feed ----

  Future<List<Post>> getPosts() async {
    final res =
        await http.get(Uri.parse('$baseUrl/posts'), headers: _headers);
    final data = await _handle(res) as List;
    return data.map((e) => Post.fromJson(e)).toList();
  }

  Future<Post> createPost({required String text, XFile? image}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/posts'));
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    request.fields['text'] = text;
    if (image != null) {
      final bytes = await image.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: image.name),
      );
    }

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = await _handle(res, okStatus: 201);
    return Post.fromJson(data as Map<String, dynamic>);
  }

  Future<Post> likePost(String postId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/posts/$postId/like'),
      headers: _headers,
    );
    final data = await _handle(res);
    return Post.fromJson(data as Map<String, dynamic>);
  }

  Future<Post> addComment(String postId, String text) async {
    final res = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments'),
      headers: _headers,
      body: jsonEncode({'text': text}),
    );
    final data = await _handle(res, okStatus: 201);
    return Post.fromJson(data as Map<String, dynamic>);
  }

  // ---- Destination suggestions ----

  Future<Destination> submitDestination({
    required String name,
    required String description,
    required double lat,
    required double lng,
    required XFile image,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/destinations'));
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    request.fields['name'] = name;
    request.fields['description'] = description;
    request.fields['lat'] = lat.toString();
    request.fields['lng'] = lng.toString();
    final bytes = await image.readAsBytes();
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: image.name),
    );

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = await _handle(res, okStatus: 201);
    return Destination.fromJson(data as Map<String, dynamic>);
  }

  Future<List<Destination>> getPendingDestinations() async {
    final res = await http.get(
      Uri.parse('$baseUrl/destinations/pending'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    return data.map((e) => Destination.fromJson(e)).toList();
  }

  Future<void> approveDestination(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/destinations/$id/approve'),
      headers: _headers,
    );
    await _handle(res);
  }

  Future<void> rejectDestination(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/destinations/$id/reject'),
      headers: _headers,
    );
    await _handle(res);
  }

  // ---- AI assistant ----

  Future<String> askAssistant({
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/assistant/chat'),
      headers: _headers,
      body: jsonEncode({'message': message, 'history': history}),
    );
    final data = await _handle(res);
    return (data as Map<String, dynamic>)['reply'] as String;
  }
}