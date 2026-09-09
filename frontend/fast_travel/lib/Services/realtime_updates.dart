import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// One authenticated connection for the app, not one poller per screen.
class RealtimeUpdates {
  RealtimeUpdates({
    required this.uri,
    required this.onInvalidate,
    required this.onUnauthorized,
    WebSocketChannel Function(Uri)? connect,
    DateTime Function()? now,
  }) : _connect = connect ?? WebSocketChannel.connect,
       _now = now ?? DateTime.now;

  final Uri uri;
  final void Function(Set<String>) onInvalidate;
  final VoidCallback onUnauthorized;
  final WebSocketChannel Function(Uri) _connect;
  final DateTime Function() _now;
  final connected = ValueNotifier(false);
  final _random = Random();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnect;
  Timer? _watchdog;
  String? _token;
  bool _active = true;
  bool _disposed = false;
  int _generation = 0;
  int _attempt = 0;
  DateTime _lastFrame = DateTime.now();

  void setToken(String? token) {
    if (_token == token) return;
    _token = token;
    _attempt = 0;
    _reset();
    if (_token != null && _active) unawaited(_open());
  }

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _reset();
    if (active && _token != null) unawaited(_open());
  }

  void retry() {
    if (_disposed || !_active || _token == null) return;
    _reset();
    unawaited(_open());
  }

  void _reset() {
    ++_generation;
    _reconnect?.cancel();
    _watchdog?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
    connected.value = false;
  }

  Future<void> _open() async {
    final generation = _generation;
    final token = _token;
    if (_disposed || !_active || token == null) return;
    try {
      final channel = _connect(uri);
      _channel = channel;
      // Attach immediately so a handshake error is handled on both futures.
      _subscription = channel.stream.listen(
        (frame) => _receive(frame, generation),
        onError: (Object error) => _lost(generation),
        onDone: () {
          if (generation != _generation) return;
          if (channel.closeCode == 4401 || channel.closeCode == 4403) {
            _reset();
            onUnauthorized();
          } else {
            _lost(generation);
          }
        },
      );
      await channel.ready.timeout(const Duration(seconds: 12));
      if (generation != _generation || _disposed) return;
      channel.sink.add(jsonEncode({'token': token}));
      _lastFrame = _now();
      _watchdog = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_now().difference(_lastFrame) >
            const Duration(seconds: 45)) {
          _lost(generation);
        } else {
          channel.sink.add(jsonEncode({'type': 'ping'}));
        }
      });
    } on WebSocketChannelException {
      _lost(generation);
    } on TimeoutException {
      _lost(generation);
    }
  }

  void _receive(dynamic frame, int generation) {
    if (generation != _generation || frame is! String) return;
    try {
      final event = jsonDecode(frame);
      if (event is! Map<String, dynamic>) {
        throw const FormatException('Expected an event object');
      }
      _lastFrame = _now();
      if (event['type'] == 'ready') {
        _attempt = 0;
        connected.value = true;
        onInvalidate({'all'});
      } else if (event['type'] == 'invalidate' && connected.value) {
        final topics = event['topics'];
        if (topics is! List || topics.any((topic) => topic is! String)) {
          throw const FormatException('Invalid topics');
        }
        onInvalidate(topics.cast<String>().toSet());
      } else if (event['type'] == 'ping') {
        _channel?.sink.add(jsonEncode({'type': 'pong'}));
      }
    } on FormatException {
      debugPrint(
          'Invalid live-update frame; reconnecting and resynchronizing.');
      _lost(generation);
    }
  }

  void _lost(int generation) {
    if (generation != _generation || _disposed) return;
    _reset();
    if (_token == null || !_active) return;
    final seconds = min(30, 1 << min(_attempt++, 5));
    _reconnect = Timer(
      Duration(milliseconds: seconds * 1000 + _random.nextInt(500)),
      () => unawaited(_open()),
    );
  }

  void dispose() {
    _disposed = true;
    _reset();
    connected.dispose();
  }
}
