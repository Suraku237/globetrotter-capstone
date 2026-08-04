// GlobeTrotter API client — typed, platform-aware, works unchanged on
// mobile, desktop, and web builds of the same Flutter app.
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;

import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  String? _token;
  void setToken(String? token) => _token = token;
  bool get isAuthenticated => _token != null;

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
    throw ApiException(detail);
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

    if (res.statusCode != 200) {
      throw ApiException('Failed to load destinations: ${res.statusCode}');
    }

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

    return rawList
        .map((e) => Destination.fromJson(e, baseUrl: baseUrl))
        .toList();
  }

  Future<List<Destination>> getRecommendations() async {
    print('📤 API: Getting recommendations');
    final res = await http.get(
      Uri.parse('$baseUrl/recommendations'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    print('✅ Got ${data.length} recommendations');
    return data.map((e) => Destination.fromJson(e, baseUrl: baseUrl)).toList();
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

    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = jsonDecode(res.body);
      print('✅ Itinerary created successfully');

      return Itinerary(
        id: data['id'] ?? 'mock_id',
        title: title,
        destinationId: destinationId,
        startDate: startDate,
        endDate: endDate,
        notes: notes,
      );
    } else {
      throw ApiException('Failed to create itinerary: ${res.statusCode}');
    }
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
}