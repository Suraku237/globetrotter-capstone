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

  // Adjust these once you know your setup:
  // - Web / desktop dev: localhost works.
  // - Android emulator: localhost on the HOST machine is 10.0.2.2 from inside the emulator.
  // - Real phone on the same Wi-Fi as your PC: use your PC's LAN IP.
  // - Production: your Contabo domain, e.g. https://api.yourdomain.com
  static String get baseUrl {
    const prodUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (prodUrl.isNotEmpty) return prodUrl;

    if (kIsWeb) return 'http://109.199.120.38:8000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://109.199.120.38:8000';
    }
    return 'http://109.199.120.38:8000'; // iOS simulator, desktop
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
    final data = await _handle(res, okStatus: 201);
    return AppUser.fromJson(data);
  }

  Future<AppUser> login(
      {required String email, required String password}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = await _handle(res);
    setToken(data['access_token'] as String);
    return AppUser.fromJson({
      'id': data['user_id'],
      'email': data['email'],
      'full_name': data['full_name'],
      'role': data['role'],
    });
  }

  Future<AppUser> loginWithGoogle({required String idToken}) async {
    print('📤 API: loginWithGoogle called');
    print('📤 Token length: ${idToken.length}');
    print('📤 Token preview: ${idToken.substring(0, 30)}...');
    print('📤 URL: $baseUrl/auth/google');

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/google'),
        headers: _headers,
        body: jsonEncode({'id_token': idToken}),
      );

      print('📥 Response status: ${res.statusCode}');
      print('📥 Response body: ${res.body}');

      if (res.statusCode != 200) {
        throw ApiException('Server returned ${res.statusCode}: ${res.body}');
      }

      final data = jsonDecode(res.body);
      print('✅ API success');

      setToken(data['access_token'] as String);
      return AppUser.fromJson({
        'id': data['user_id'],
        'email': data['email'],
        'full_name': data['full_name'],
        'role': data['role'],
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
    final data = await _handle(res) as List;
    return data.map((e) => Destination.fromJson(e)).toList();
  }

  Future<List<Destination>> getRecommendations() async {
    final res = await http.get(
      Uri.parse('$baseUrl/recommendations'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    return data.map((e) => Destination.fromJson(e)).toList();
  }

  Future<Itinerary> createItinerary({
    required String title,
    required String destinationId,
    required String startDate,
    required String endDate,
    String? notes,
  }) async {
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
    return Itinerary.fromJson(data);
  }

  Future<List<Itinerary>> getItineraries() async {
    final res = await http.get(
      Uri.parse('$baseUrl/itineraries'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    return data.map((e) => Itinerary.fromJson(e)).toList();
  }
}
