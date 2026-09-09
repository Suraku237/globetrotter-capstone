import 'dart:async';

/// Coalesces cache/live notifications without losing a change during a fetch.
class LiveRefresh {
  LiveRefresh({
    required Stream<Set<String>> changes,
    required Set<String> topics,
    required Future<void> Function() onRefresh,
  }) : _onRefresh = onRefresh {
    _subscription = changes.listen((changed) {
      if (changed.contains('all') || changed.any(topics.contains)) {
        unawaited(refresh());
      }
    });
  }

  final Future<void> Function() _onRefresh;
  late final StreamSubscription<Set<String>> _subscription;
  Future<void>? _running;
  bool _queued = false;
  bool _disposed = false;

  Future<void> refresh() {
    if (_disposed) return Future.value();
    _queued = true;
    return _running ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_queued && !_disposed) {
        _queued = false;
        await _onRefresh();
      }
    } finally {
      _running = null;
    }
  }

  void dispose() {
    _disposed = true;
    _queued = false;
    unawaited(_subscription.cancel());
  }
}
