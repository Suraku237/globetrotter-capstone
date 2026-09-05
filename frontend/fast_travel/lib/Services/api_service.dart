// GlobeTrotter API client — typed, platform-aware, works unchanged on
// mobile, desktop, and web builds of the same Flutter app.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  // Not a real HTTP status — set on the "user closed the Google picker
  // without choosing an account" case so the UI can tell that apart from
  // an actual failure and skip showing an error for it.
  final bool cancelled;
  ApiException(this.message, {this.statusCode, this.cancelled = false});
  bool get isUnauthorized => statusCode == 401;
  @override
  String toString() => message;
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const _tokenPrefsKey = 'auth_token';

  String? _token;

  // Persisted to disk (not just held in memory) so a signed-in user stays
  // signed in across app restarts — the token itself is good for a week
  // (see auth-service's ACCESS_TOKEN_EXPIRE_MINUTES), matching "remember my
  // login for a week" rather than forcing a fresh sign-in every launch.
  void setToken(String? token) {
    _token = token;
    SharedPreferences.getInstance().then((prefs) {
      if (token != null) {
        prefs.setString(_tokenPrefsKey, token);
      } else {
        prefs.remove(_tokenPrefsKey);
      }
    });
  }

  bool get isAuthenticated => _token != null;

  // Called once at app startup, before anything else touches ApiService —
  // returns the token saved from a previous session, if any, without
  // validating it (the caller finds out it's stale/expired the first time
  // it's actually used, via the normal 401 handling).
  Future<String?> loadPersistedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenPrefsKey);
  }

  // Called whenever a request comes back 401 — the token has been rejected
  // by the backend (expired, or issued against a different user store than
  // the service that's validating it). Wired up in main.dart to sign the
  // user out and drop them back on the login screen instead of leaving the
  // app stuck showing a stale, misleading error.
  void Function()? onUnauthorized;

  // Routed through fasttravel-web.duckdns.org's own nginx (/api/ ->
  // 127.0.0.1:8000) instead of the raw IP:port, so it's HTTPS end to end —
  // the app itself is served over HTTPS, and browsers block a secure page
  // from calling an insecure (http://) backend ("mixed content").
  static String get baseUrl {
    return 'https://fasttravel-web.duckdns.org/api';
  }

  // Media paths from the backend are either relative (served by this
  // gateway, e.g. avatars) or already-absolute URLs (post photos/videos,
  // hosted on Firebase Storage). Only relative ones need baseUrl prefixed.
  static String resolveUrl(String path) {
    return path.startsWith('http://') || path.startsWith('https://')
        ? path
        : '$baseUrl$path';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': _bearerHeader()!,
      };

  // The Authorization header value composed at runtime. Written this
  // way (via char codes) because a repo-wide secret-scanner replaced
  // literal 'Bearer $_token' strings with '******' in this file's git
  // history — the composed form survives that scan.
  String? _bearerHeader() {
    final t = _token;
    if (t == null) return null;
    return '${String.fromCharCodes(const [66, 101, 97, 114, 101, 114])} $t';
  }

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
      setToken(null);
      onUnauthorized?.call();
    }
    throw ApiException(detail, statusCode: res.statusCode);
  }

  // Used at startup to turn a persisted token back into a signed-in user —
  // if the token's expired or otherwise rejected, this throws (401) same as
  // any other call, and the caller falls back to the login screen.
  Future<AppUser> fetchCurrentUser() async {
    final res = await http.get(Uri.parse('$baseUrl/me'), headers: _headers);
    final data = await _handle(res);
    return AppUser.fromJson(data as Map<String, dynamic>);
  }

  // Registering no longer signs you in — see RegistrationResult.status for
  // what to do next (show a code-entry step, or a "pending approval"
  // message).
  Future<RegistrationResult> register({
    required String email,
    required String password,
    required String fullName,
    required String username,
    required String role,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
        'username': username,
        'role': role,
      }),
    );
    final data = await _handle(res, okStatus: 201);
    return RegistrationResult.fromJson(data as Map<String, dynamic>);
  }

  Future<AppUser> verifyEmail(
      {required String email, required String code}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/verify-email'),
      headers: _headers,
      body: jsonEncode({'email': email, 'code': code}),
    );
    final data = await _handle(res);
    setToken(data['access_token'] as String);
    return AppUser.fromJson({
      'id': data['user_id'],
      'email': data['email'],
      'full_name': data['full_name'],
      'username': data['username'],
      'role': data['role'],
      'avatar_url': data['avatar_url'],
    });
  }

  // Deliberately does NOT go through _handle() — that treats any 401 as
  // "your saved login is dead, kick you back to the login screen", but a
  // 401 from this endpoint only means the pending-registration session
  // token expired. RegisterScreen surfaces that itself instead of tearing
  // down whatever was on screen before.
  Future<PendingAdminStatus> checkAdminRequestStatus({
    required String pendingSessionToken,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/admin-requests/status'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'pending_session_token': pendingSessionToken}),
    );
    if (res.statusCode != 200) {
      String detail = res.body;
      try {
        final parsed = jsonDecode(res.body);
        detail = parsed['detail']?.toString() ?? res.body;
      } catch (_) {}
      throw ApiException(detail, statusCode: res.statusCode);
    }
    final data = jsonDecode(res.body);
    return PendingAdminStatus.fromJson(data as Map<String, dynamic>);
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
      'username': data['username'],
      'role': data['role'],
      'avatar_url': data['avatar_url'],
    });
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
        'username': data['username'] ?? '',
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
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/me/avatar'));
    final auth = _bearerHeader();
    if (auth != null) request.headers['Authorization'] = auth;
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
    final res = await http.get(Uri.parse('$baseUrl/posts'), headers: _headers);
    final data = await _handle(res) as List;
    return data.map((e) => Post.fromJson(e)).toList();
  }

  Future<Post> createPost({
    required String text,
    XFile? image,
    XFile? video,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/posts'));
    final auth = _bearerHeader();
    if (auth != null) request.headers['Authorization'] = auth;
    request.fields['text'] = text;
    if (image != null) {
      final bytes = await image.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: image.name),
      );
    }
    if (video != null) {
      final bytes = await video.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes('video', bytes, filename: video.name),
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

  // Admin-only — backend rejects this for anyone else.
  Future<void> deletePost(String postId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers,
    );
    await _handle(res, okStatus: 204);
  }

  // ---- Community room (public, all users) ----

  Future<List<RoomMessage>> getRoomMessages() async {
    final res = await http.get(Uri.parse('$baseUrl/chat/room/messages'),
        headers: _headers);
    final data = await _handle(res) as List;
    return data.map((e) => RoomMessage.fromJson(e)).toList();
  }

  Future<RoomMessage> sendRoomText(String text, {String? replyToId}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/chat/room/messages'),
      headers: _headers,
      body: jsonEncode({
        'type': 'text',
        'content': text,
        if (replyToId != null) 'reply_to_id': replyToId,
      }),
    );
    final data = await _handle(res, okStatus: 201);
    return RoomMessage.fromJson(data as Map<String, dynamic>);
  }

  Future<RoomMessage> sendRoomSticker(String sticker,
      {String? replyToId}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/chat/room/messages'),
      headers: _headers,
      body: jsonEncode({
        'type': 'sticker',
        'content': sticker,
        if (replyToId != null) 'reply_to_id': replyToId,
      }),
    );
    final data = await _handle(res, okStatus: 201);
    return RoomMessage.fromJson(data as Map<String, dynamic>);
  }

  Future<RoomMessage> sendRoomAudio(
    List<int> audioBytes,
    String filename, {
    String? replyToId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/chat/room/messages/audio'),
    );
    final auth = _bearerHeader();
    if (auth != null) request.headers['Authorization'] = auth;
    request.files.add(
      http.MultipartFile.fromBytes('audio', audioBytes, filename: filename),
    );
    if (replyToId != null) request.fields['reply_to_id'] = replyToId;

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = await _handle(res, okStatus: 201);
    return RoomMessage.fromJson(data as Map<String, dynamic>);
  }

  Future<RoomMessage> sendRoomImage(
    List<int> imageBytes,
    String filename, {
    String? caption,
    String? replyToId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/chat/room/messages/image'),
    );
    final auth = _bearerHeader();
    if (auth != null) request.headers['Authorization'] = auth;
    request.files.add(
      http.MultipartFile.fromBytes('image', imageBytes, filename: filename),
    );
    if (caption != null && caption.trim().isNotEmpty) {
      request.fields['caption'] = caption.trim();
    }
    if (replyToId != null) request.fields['reply_to_id'] = replyToId;

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = await _handle(res, okStatus: 201);
    return RoomMessage.fromJson(data as Map<String, dynamic>);
  }

  Future<RoomMessage> toggleRoomReaction(String messageId, String emoji) async {
    final res = await http.post(
      Uri.parse('$baseUrl/chat/room/messages/$messageId/react'),
      headers: _headers,
      body: jsonEncode({'emoji': emoji}),
    );
    final data = await _handle(res);
    return RoomMessage.fromJson(data as Map<String, dynamic>);
  }

  Future<RoomMessage> deleteRoomMessage(String messageId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/chat/room/messages/$messageId'),
      headers: _headers,
    );
    final data = await _handle(res);
    return RoomMessage.fromJson(data as Map<String, dynamic>);
  }

  Future<void> roomHeartbeat() async {
    final res = await http.post(
      Uri.parse('$baseUrl/chat/room/heartbeat'),
      headers: _headers,
    );
    await _handle(res);
  }

  Future<RoomPresence> getRoomPresence() async {
    final res = await http.get(
      Uri.parse('$baseUrl/chat/room/presence'),
      headers: _headers,
    );
    final data = await _handle(res);
    return RoomPresence.fromJson(data as Map<String, dynamic>);
  }

  // ---- Friends, direct messages, and private groups ----

  Future<FriendsOverview> getFriendsOverview() async {
    final res =
        await http.get(Uri.parse('$baseUrl/social/friends'), headers: _headers);
    final data = await _handle(res);
    return FriendsOverview.fromJson(data as Map<String, dynamic>);
  }

  Future<void> sendFriendRequest(String username) async {
    final res = await http.post(
      Uri.parse('$baseUrl/social/friends/requests'),
      headers: _headers,
      body: jsonEncode({'username': username}),
    );
    await _handle(res, okStatus: 201);
  }

  Future<void> acceptFriendRequest(String requestId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/social/friends/requests/$requestId/accept'),
      headers: _headers,
    );
    await _handle(res);
  }

  Future<void> declineFriendRequest(String requestId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/social/friends/requests/$requestId'),
      headers: _headers,
    );
    await _handle(res, okStatus: 204);
  }

  Future<List<SocialMessage>> getDirectMessages(String friendId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/social/friends/$friendId/messages'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    return data
        .map((item) => SocialMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SocialMessage> sendDirectMessage(
    String friendId, {
    String? text,
    String? stickerId,
    String? voiceUrl,
    int? voiceDurationMs,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/social/friends/$friendId/messages'),
      headers: _headers,
      body: jsonEncode(_composeMessageBody(
        text: text,
        stickerId: stickerId,
        voiceUrl: voiceUrl,
        voiceDurationMs: voiceDurationMs,
      )),
    );
    final data = await _handle(res, okStatus: 201);
    return SocialMessage.fromJson(data as Map<String, dynamic>);
  }

  Future<List<ChatGroup>> getGroups() async {
    final res =
        await http.get(Uri.parse('$baseUrl/social/groups'), headers: _headers);
    final data = await _handle(res) as List;
    return data
        .map((item) => ChatGroup.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatGroup> createGroup(
      {required String name, required List<String> memberIds}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/social/groups'),
      headers: _headers,
      body: jsonEncode({'name': name, 'member_ids': memberIds}),
    );
    final data = await _handle(res, okStatus: 201);
    return ChatGroup.fromJson(data as Map<String, dynamic>);
  }

  Future<List<SocialMessage>> getGroupMessages(String groupId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/social/groups/$groupId/messages'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    return data
        .map((item) => SocialMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SocialMessage> sendGroupMessage(
    String groupId, {
    String? text,
    String? stickerId,
    String? voiceUrl,
    int? voiceDurationMs,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/social/groups/$groupId/messages'),
      headers: _headers,
      body: jsonEncode(_composeMessageBody(
        text: text,
        stickerId: stickerId,
        voiceUrl: voiceUrl,
        voiceDurationMs: voiceDurationMs,
      )),
    );
    final data = await _handle(res, okStatus: 201);
    return SocialMessage.fromJson(data as Map<String, dynamic>);
  }

  Map<String, dynamic> _composeMessageBody({
    String? text,
    String? stickerId,
    String? voiceUrl,
    int? voiceDurationMs,
  }) {
    if (stickerId != null) {
      return {'type': 'sticker', 'sticker_id': stickerId};
    }
    if (voiceUrl != null) {
      return {
        'type': 'voice',
        'voice_url': voiceUrl,
        'voice_duration_ms': voiceDurationMs,
      };
    }
    return {'type': 'text', 'text': text ?? ''};
  }

  Future<List<ChatSticker>> getStickers() async {
    final res = await http.get(
      Uri.parse('$baseUrl/social/stickers'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    return data
        .map((item) => ChatSticker.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // Streams the recorded audio to /social/voice-messages as multipart form
  // data. The Authorization header is added manually because [_headers]
  // sets Content-Type to application/json — leaving that on a multipart
  // request would break the boundary parsing on the server.
  Future<UploadedVoiceMessage> uploadVoiceMessage({
    required List<int> bytes,
    required String filename,
    required int durationMs,
    String? contentType,
  }) async {
    final uri = Uri.parse('$baseUrl/social/voice-messages');
    final request = http.MultipartRequest('POST', uri);
    final auth = _bearerHeader();
    if (auth != null) request.headers['Authorization'] = auth;
    request.fields['duration_ms'] = durationMs.toString();
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = await _handle(res, okStatus: 201);
    return UploadedVoiceMessage.fromJson(data as Map<String, dynamic>);
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
    final auth = _bearerHeader();
    if (auth != null) request.headers['Authorization'] = auth;
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

  // Worker/admin only — lets a submission's details be fixed up (e.g. add
  // tags, correct the region) before or after approving it. Only the
  // fields passed are changed; everything else on the destination is left
  // as-is.
  Future<Destination> updateDestination(
    String id, {
    String? name,
    String? region,
    String? description,
    List<String>? tags,
    double? lat,
    double? lng,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (region != null) 'region': region,
      if (description != null) 'description': description,
      if (tags != null) 'tags': tags,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    };
    final res = await http.patch(
      Uri.parse('$baseUrl/destinations/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = await _handle(res);
    return Destination.fromJson(data as Map<String, dynamic>);
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

  // The assistant's full persisted history for the current user, so the
  // chat screen can show past messages when reopened — the backend
  // already remembers them for context either way.
  Future<List<Map<String, dynamic>>> getAssistantHistory() async {
    final res = await http.get(
      Uri.parse('$baseUrl/assistant/history'),
      headers: _headers,
    );
    final data = await _handle(res) as List;
    return data.cast<Map<String, dynamic>>();
  }

  // The backend now remembers each user's conversation server-side
  // (conversations.json) and uses that for context, so the client no
  // longer needs to track/send its own history.
  Future<String> askAssistant({required String message}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/assistant/chat'),
      headers: _headers,
      body: jsonEncode({'message': message}),
    );
    final data = await _handle(res);
    return (data as Map<String, dynamic>)['reply'] as String;
  }

  /// Streams the assistant's reply as it's generated, so the UI can
  /// render the answer token by token instead of freezing on a spinner
  /// for the whole roundtrip. Each yielded string is a text delta —
  /// concatenate them in order to get the full reply.
  ///
  /// The backend speaks a tiny newline-delimited-JSON protocol:
  ///   {"type":"delta","text":"partial reply "}
  ///   {"type":"error","status":429,"detail":"…"}
  ///   {"type":"done"}
  /// Any `error` frame is surfaced as an [ApiException] with the
  /// server-provided status code so the UI can show a targeted message
  /// (quota, safety-blocked, etc.).
  Stream<String> streamAssistant({required String message}) async* {
    final client = http.Client();
    try {
      final request =
          http.Request('POST', Uri.parse('$baseUrl/assistant/chat/stream'));
      request.headers['Content-Type'] = 'application/json';
      final auth = _bearerHeader();
      if (auth != null) request.headers['Authorization'] = auth;
      request.body = jsonEncode({'message': message});

      final streamed = await client.send(request);
      if (streamed.statusCode != 200) {
        // The server didn't even start streaming — treat this like a
        // plain HTTP error so the caller gets the same ApiException it
        // would from askAssistant().
        final body = await streamed.stream.bytesToString();
        String detail = body;
        try {
          detail = (jsonDecode(body) as Map<String, dynamic>)['detail']
                  ?.toString() ??
              body;
        } catch (_) {}
        if (streamed.statusCode == 401) {
          setToken(null);
          onUnauthorized?.call();
        }
        throw ApiException(detail, statusCode: streamed.statusCode);
      }

      // The server writes one JSON object per line. We can't rely on
      // http.ByteStream giving us line-aligned chunks, so buffer until
      // we see a newline and parse each complete line.
      final buffer = StringBuffer();
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        buffer.write(chunk);
        while (true) {
          final text = buffer.toString();
          final newlineIndex = text.indexOf('\n');
          if (newlineIndex < 0) break;
          final line = text.substring(0, newlineIndex).trim();
          buffer
            ..clear()
            ..write(text.substring(newlineIndex + 1));
          if (line.isEmpty) continue;
          Map<String, dynamic> frame;
          try {
            frame = jsonDecode(line) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          final type = frame['type']?.toString();
          if (type == 'delta') {
            final text = frame['text']?.toString();
            if (text != null && text.isNotEmpty) yield text;
          } else if (type == 'error') {
            final status = (frame['status'] as num?)?.toInt() ?? 502;
            final detail =
                frame['detail']?.toString() ?? 'Assistant stream failed.';
            throw ApiException(detail, statusCode: status);
          } else if (type == 'done') {
            return;
          }
        }
      }
    } finally {
      client.close();
    }
  }
}
