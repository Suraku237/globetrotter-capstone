import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'preference_storage.dart';

class CacheConnectionException implements Exception {
  CacheConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Bounded, account-scoped JSON cache. Mutations and call signalling never use it.
class CachedApiClient extends http.BaseClient {
  CachedApiClient({
    required this.baseUrl,
    required this.onChanged,
    required this.onUnauthorized,
    required this.connectionError,
    http.Client? network,
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
    this.maxBytes = 4 * 1024 * 1024,
    this.maxEntries = 80,
  })  : _network = network ?? http.Client(),
        _preferences = preferences ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now;

  static const storageKey = 'offline_responses_v1';
  final String baseUrl;
  final void Function(Set<String>) onChanged;
  final VoidCallback onUnauthorized;
  final CacheConnectionException Function(String) connectionError;
  final http.Client _network;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  final int maxBytes;
  final int maxEntries;
  final unavailable = ValueNotifier(false);
  final storageWarning = ValueNotifier(false);
  final Map<String, _Entry> _entries = {};
  final Map<String, Future<http.Response>> _pending = {};
  final Map<String, int> _revisions = {};
  final Map<String, DateTime> _retryAfter = {};
  String? _scope;
  bool _scopeInitialized = false;
  int _generation = 0;
  Future<void> _ready = Future.value();
  Future<void> _writes = Future.value();
  Timer? _persistTimer;

  Future<void> setScope(String? scope, {bool reset = false}) {
    if (!reset && _scopeInitialized && _scope == scope) return _ready;
    _scopeInitialized = true;
    _scope = scope;
    final generation = ++_generation;
    _entries.clear();
    _pending.clear();
    _revisions.clear();
    _retryAfter.clear();
    unavailable.value = false;
    _persistTimer?.cancel();
    return _ready = _restore(scope, generation, _writes);
  }

  Future<void> _restore(String? scope, int generation, Future<void> writes) async {
    try {
      await _readStored(scope, generation, writes);
    } on PreferenceStorageException {
      if (generation != _generation) return;
      _entries.clear();
      storageWarning.value = true;
    }
  }

  Future<void> _readStored(String? scope, int generation, Future<void> writes) async {
    await writes;
    final prefs = await preferenceStorage(_preferences);
    if (generation != _generation) return;
    final stored = prefs.getString(storageKey);
    if (scope == null) {
      if (!await preferenceStorage(() => prefs.remove(storageKey))) storageWarning.value = true;
      return;
    }
    if (stored == null) return;
    try {
      final data = jsonDecode(stored) as Map<String, dynamic>;
      if (data['scope'] != scope) {
        if (!await preferenceStorage(() => prefs.remove(storageKey))) storageWarning.value = true;
        return;
      }
      for (final item in (data['entries'] as Map<String, dynamic>).entries) {
        final entry = _Entry.fromJson(item.value as Map<String, dynamic>);
        if (_now().difference(entry.saved) <= const Duration(days: 7)) {
          _entries[item.key] = entry;
        }
      }
      _trim();
    } on FormatException {
      _entries.clear();
      storageWarning.value = true;
      await preferenceStorage(() => prefs.remove(storageKey));
    } on TypeError {
      _entries.clear();
      storageWarning.value = true;
      await preferenceStorage(() => prefs.remove(storageKey));
    }
  }

  Future<void> prime(Uri uri, Map<String, dynamic> data) async {
    final generation = _generation;
    await _ready;
    if (_scope == null || generation != _generation) return;
    final cacheTopic = topic(uri);
    if (cacheTopic == null) throw ArgumentError.value(uri, 'uri', 'Not cacheable');
    _revisions[cacheTopic] = (_revisions[cacheTopic] ?? 0) + 1;
    _entries[uri.toString()] = _Entry(jsonEncode(data), cacheTopic, _now());
    _trim();
    await flush();
  }

  String? topic(Uri uri) {
    if (!uri.toString().startsWith('$baseUrl/')) return null;
    final path = uri.path.substring(Uri.parse(baseUrl).path.length);
    if (path == '/me') return 'profile';
    if (path == '/posts') return 'posts';
    if (path == '/destinations') return 'destinations';
    if (path == '/recommendations') return 'recommendations';
    if (path == '/itineraries') return 'itineraries';
    if (path == '/assistant/history') return 'assistant';
    if (path == '/chat/room/messages') return 'chat';
    if (path == '/social/stickers') return 'stickers';
    if (path == '/social/friends' || path == '/social/groups' ||
        RegExp(r'^/social/(friends|groups)/[^/]+/messages$').hasMatch(path)) {
      return 'friends';
    }
    return null;
  }

  Set<String> mutationTopics(Uri uri) {
    final path = uri.path.substring(Uri.parse(baseUrl).path.length);
    if (path.startsWith('/social/calls') ||
        path.startsWith('/social/call-devices') ||
        path.endsWith('/heartbeat')) return {};
    if (path.startsWith('/social/')) return {'friends'};
    if (path.startsWith('/chat/')) return {'chat'};
    if (path.startsWith('/posts')) return {'posts', 'stats'};
    if (path.startsWith('/destinations')) {
      return {'destinations', 'recommendations', 'stats'};
    }
    if (path.startsWith('/itineraries')) {
      return {'itineraries', 'recommendations'};
    }
    if (path.startsWith('/me')) return {'profile', 'friends', 'posts', 'chat'};
    if (path.startsWith('/assistant/')) return {'assistant'};
    return {};
  }

  void invalidate(Set<String> topics) {
    for (final entry in _entries.values) {
      if (topics.contains('all') || topics.contains(entry.topic)) {
        entry.dirty = true;
      }
    }
    for (final topic in {..._revisions.keys, ...topics}) {
      if (topics.contains('all') || topics.contains(topic)) {
        _revisions[topic] = (_revisions[topic] ?? 0) + 1;
      }
    }
    _retryAfter.clear();
    if (topics.isNotEmpty) onChanged(topics);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final generation = _generation;
    await _ready;
    if (generation != _generation) {
      throw connectionError('The sign-in session changed.');
    }
    final cacheTopic = request.method == 'GET' && _scope != null
        ? topic(request.url)
        : null;
    if (cacheTopic == null) {
      final response = await _fetch(request, generation);
      if (response.statusCode >= 200 && response.statusCode < 300 &&
          request.method != 'GET') {
        if (request.url.toString() == '$baseUrl/me' ||
            request.url.toString() == '$baseUrl/me/avatar') {
          await prime(Uri.parse('$baseUrl/me'),
              jsonDecode(response.body) as Map<String, dynamic>);
        }
        invalidate(mutationTopics(request.url));
      }
      return _stream(response);
    }
    final key = request.url.toString();
    _revisions.putIfAbsent(cacheTopic, () => 0);
    final entry = _entries.remove(key);
    if (entry != null && _now().difference(entry.saved) <= const Duration(days: 7)) {
      _entries[key] = entry;
      final age = _now().difference(entry.saved);
      final ttl = cacheTopic == 'stickers'
          ? const Duration(hours: 12)
          : const Duration(seconds: 60);
      if ((entry.dirty || age > ttl) &&
          !(_retryAfter[key]?.isAfter(_now()) ?? false)) {
        unawaited(_refreshInBackground(request, cacheTopic));
      }
      return _stream(http.Response(entry.body, 200,
          request: request, headers: const {'content-type': 'application/json; charset=utf-8'}));
    }
    return _stream(await _refresh(request, cacheTopic));
  }

  Future<void> _refreshInBackground(http.BaseRequest request, String topic) async {
    try {
      await _refresh(request, topic);
    } on CacheConnectionException catch (error) {
      // The cached value remains readable, but the app displays offline status.
      debugPrint('Background cache refresh failed: ${error.runtimeType}');
    }
  }

  Future<http.Response> _refresh(http.BaseRequest request, String topic) {
    final key = request.url.toString();
    final existing = _pending[key];
    if (existing != null) return existing;
    final generation = _generation;
    final revision = _revisions[topic] ?? 0;
    final future = _refreshOnce(request, topic, generation, revision);
    _pending[key] = future;
    return future;
  }

  Future<http.Response> _refreshOnce(
      http.BaseRequest request, String topic, int generation, int revision) async {
    final key = request.url.toString();
    try {
      final response = await _fetch(request, generation);
      if (generation != _generation) {
        throw connectionError('The sign-in session changed.');
      }
      if (response.statusCode == 200 && revision == _revisions[topic]) {
        final previous = _entries[key]?.body;
        _entries.remove(key);
        _entries[key] = _Entry(response.body, topic, _now());
        _trim();
        _schedulePersist();
        if (previous != null && previous != response.body) onChanged({topic});
      } else if (response.statusCode == 401 || response.statusCode == 403 ||
          response.statusCode == 404) {
        final removed = _entries.remove(key);
        _schedulePersist();
        if (removed != null) onChanged({topic});
      }
      return response;
    } finally {
      if (generation == _generation) {
        _pending.remove(key);
        if (revision != _revisions[topic]) onChanged({topic});
      }
    }
  }

  Future<http.Response> _fetch(http.BaseRequest request, int generation) async {
    try {
      final timeout = request is http.MultipartRequest
          ? const Duration(minutes: 2)
          : request.url.path.contains('/assistant/')
              ? const Duration(seconds: 90)
              : const Duration(seconds: 15);
      final response = await _network.send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (generation != _generation) {
        throw connectionError('The sign-in session changed.');
      }
      unavailable.value = response.statusCode >= 500;
      if (response.statusCode >= 500) {
        _retryAfter[request.url.toString()] = _now().add(const Duration(seconds: 30));
      }
      if (response.statusCode == 401 &&
          request.headers.containsKey('Authorization')) onUnauthorized();
      return response;
    } on TimeoutException {
      if (generation == _generation) _failed(request.url);
      throw connectionError('Connection timed out. Saved content is still available.');
    } on http.ClientException {
      if (generation == _generation) _failed(request.url);
      throw connectionError('Cannot connect. Check your connection and try again.');
    }
  }

  void _failed(Uri uri) {
    unavailable.value = true;
    _retryAfter[uri.toString()] = _now().add(const Duration(seconds: 30));
  }

  http.StreamedResponse _stream(http.Response response) => http.StreamedResponse(
      Stream.value(response.bodyBytes), response.statusCode,
      headers: response.headers, request: response.request);

  void _trim() {
    while (_entries.isNotEmpty &&
        (_entries.length > maxEntries || utf8.encode(_encode()).length > maxBytes)) {
      // Keep the profile so browsing many pages cannot prevent an offline launch.
      final key = _entries.keys.firstWhere(
          (key) => _entries[key]!.topic != 'profile',
          orElse: () => _entries.keys.first);
      _entries.remove(key);
    }
  }

  String _encode() => jsonEncode({
    'scope': _scope,
    'entries': _entries.map((key, value) => MapEntry(key, value.toJson())),
  });

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _persistTimer?.cancel();
    if (!_scopeInitialized) return;
    final generation = _generation;
    await _ready;
    if (generation != _generation) return;
    final scope = _scope;
    final encoded = _encode();
    return _writes = _writes.then((_) async {
      try {
        final prefs = await preferenceStorage(_preferences);
        if (generation != _generation) return;
        final success = scope == null
            ? await preferenceStorage(() => prefs.remove(storageKey))
            : await preferenceStorage(() => prefs.setString(storageKey, encoded));
        storageWarning.value = !success;
      } on PreferenceStorageException {
        storageWarning.value = true;
      }
    });
  }

  @override
  void close() {
    _persistTimer?.cancel();
    _network.close();
    unavailable.dispose();
    storageWarning.dispose();
    super.close();
  }
}

class _Entry {
  _Entry(this.body, this.topic, this.saved, {this.dirty = false});
  final String body;
  final String topic;
  final DateTime saved;
  bool dirty;

  factory _Entry.fromJson(Map<String, dynamic> data) => _Entry(
      data['body'] as String, data['topic'] as String,
      DateTime.parse(data['saved'] as String), dirty: true);

  Map<String, dynamic> toJson() =>
      {'body': body, 'topic': topic, 'saved': saved.toIso8601String()};
}
