import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:livekit_client/livekit_client.dart' show Room;

import '../models/call_models.dart';
import '../screens/friends/call_screen.dart';
import 'api_service.dart';
import 'call_push_service.dart';
import 'package:fast_travel/Services/call_media_session.dart';
import 'session_state.dart';

/// One call owner across tabs, notification launches and account changes.
class CallCoordinator with WidgetsBindingObserver {
  static late final CallCoordinator instance;

  final SessionState session;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final ApiService _api;
  final DateTime Function() _now;
  final Room Function()? _roomFactory;
  bool _uiAvailable;
  CallMediaSession? _media;
  CallConnection? _connection;
  String? _pendingCallId;
  final Map<String, bool> _muteStates = {};
  CallMediaSession? get media => _media;
  final ValueNotifier<CallSession?> callState = ValueNotifier(null);
  Future<void> Function()? beforeConnect;
  bool get isInCall => _busy || callState.value != null;
  late final CallPushService _push;
  Timer? _poller;
  StreamSubscription<Set<String>>? _updates;
  bool _refreshQueued = false;
  bool _foreground = true;
  DateTime _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);
  Route<void>? _incomingRoute;
  Route<void>? _callRoute;
  bool _polling = false;
  bool _busy = false;
  bool _disposed = false;
  bool _signedOut = false;
  int _generation = 0;
  String? _userId;
  String? _lastPollError;
  String? _pendingNotice;
  DateTime _lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _leaveFuture;
  Future<void>? _initializing;

  CallCoordinator({
    required this.session,
    required this.navigatorKey,
    required this.messengerKey,
    ApiService? api,
    CallPushService? push,
    Room Function()? roomFactory,
    DateTime Function()? now,
    bool uiAvailable = true,
  }) : _api = api ?? ApiService.instance,
       _now = now ?? DateTime.now,
       _roomFactory = roomFactory,
       _uiAvailable = uiAvailable {
    _push = push ??
        CallPushService(
          onIncoming: _incoming,
          onAccept: _accept,
          onDecline: _decline,
          onError: _notify,
          onMuteChanged: _nativeMute,
          onEnded: _remoteEnded,
        );
  }

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    await _push.initialize();
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    session.addListener(_sessionChanged);
    _sessionChanged();
    _updates = _api.changes.listen((topics) {
      if (!topics.contains('calls') && !topics.contains('all')) return;
      _requestRefresh();
    });
    _poller = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_foreground && callState.value == null) return;
      final interval = !_api.isLive ? 3 : (callState.value == null ? 30 : 10);
      if (_now().difference(_lastPoll).inSeconds >= interval) {
        unawaited(_poll());
      }
    });
  }

  void _notify(String message) {
    if (_disposed) return;
    final messenger = messengerKey.currentState;
    if (!_uiAvailable || messenger == null) {
      _pendingNotice = message;
    } else {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _sessionChanged() {
    final next = session.currentUser?.id;
    if (next == _userId) return;
    _generation++;
    _userId = next;
    _signedOut = next == null;
    if (next == null) {
      unawaited(signOut());
    } else {
      _leaveFuture = null;
      unawaited(_registerAndPoll());
    }
  }

  Future<void> _registerAndPoll() async {
    try {
      // No permission dialog, Navigator or frame is needed to consume a
      // lock-screen answer after authenticated session restoration.
      await _push.restoreSession();
    } catch (error) {
      _notify('Call recovery failed. Please check your connection.');
    }
    _refreshQueued = true;
    await _poll();
  }

  void setUiAvailable(bool available) {
    _uiAvailable = available;
    if (available) {
      final notice = _pendingNotice;
      _pendingNotice = null;
      if (notice != null) _notify(notice);
      _presentMedia();
      _requestRefresh();
    }

  }

  Future<void> acceptIncoming(String id) => _accept(id);
  Future<void> endIncoming(String id) => _decline(id);
  Future<void> updateNativeMute(String id, bool muted) => _nativeMute(id, muted);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      if (_uiAvailable) _presentMedia();
      _requestRefresh();
    }
  }

  Future<void> enableNotifications() async {
    if (!session.isSignedIn || _signedOut) {
      _notify('Sign in to enable call notifications.');
      return;
    }
    try {
      await _push.registerDevice();
    } on ApiException catch (error) {
      _notify('Call notifications: ${error.message}');
    }
  }

  Future<void> startCall({
    required CallKind kind,
    required String targetType,
    required String targetId,
  }) async {
    if (_busy || callState.value != null) {
      _notify('Finish your current call first.');
      return;
    }
    if (!session.isSignedIn) {
      _notify('Sign in to make a call.');
      return;
    }
    _busy = true;
    final userId = session.currentUser!.id;
    final generation = _generation;
    try {
      await beforeConnect?.call();
      if (!_sameSession(userId, generation)) return;
      final call = await _api.createCall(
          kind: kind, targetType: targetType, targetId: targetId);
      if (!_sameSession(userId, generation)) {
        if (_api.isAuthenticated && session.currentUser?.id == userId) {
          await _api.updateCall(call.id, 'leave');
        }
        return;
      }
      callState.value = call;
      _leaveFuture = null;
      final connection = await _api.connectCall(call.id, accept: false);
      if (!_sameSession(userId, generation)) return;
      await _beginMedia(connection);
    } on ApiException catch (error) {
      _notify(error.message);
      await _leave();
      callState.value = null;
    } catch (_) {
      _notify('Call media could not start. Check permissions and try again.');
      await _leave();
    } finally {
      _busy = false;
      if (_refreshQueued) unawaited(_poll());
    }

  }

  bool _sameSession(String userId, int generation) =>
      !_disposed &&
      !_signedOut &&
      _generation == generation &&
      session.currentUser?.id == userId;

  void _requestRefresh() {
    if (_disposed || _signedOut || !session.isSignedIn) return;
    _refreshQueued = true;
    unawaited(_poll());
  }

  Future<void> _poll() async {
    if (_polling ||
        _busy ||
        _signedOut ||
        !session.isSignedIn ||
        _disposed ||
        (!_foreground && callState.value == null)) {
      return;
    }
    _polling = true;
    _refreshQueued = false;
    _lastPoll = _now();
    final userId = session.currentUser!.id;
    final generation = _generation;
    try {
      final current = callState.value;
      if (current != null) {
        if (current.isEnded) return;
        final heartbeat = _media != null && !_media!.closing &&
            _now().difference(_lastHeartbeat).inSeconds >= 10;
        final updated = heartbeat
            ? await _api.updateCall(current.id, 'heartbeat')
            : await _api.getCall(current.id);
        if (!_sameSession(userId, generation) ||
            callState.value?.id != current.id ||
            callState.value?.isEnded == true) {
          return;
        }
        if (heartbeat) _lastHeartbeat = _now();
        callState.value = updated;
        if (updated.isEnded) {
          await _remoteEnded(updated.id);
        }
      } else {
        final incoming = await _api.getIncomingCalls();
        if (!_sameSession(userId, generation)) return;
        for (final call in incoming) {
          if (call.canAnswer(userId, _now())) {
            await _presentIncoming(call);
            break;
          }
        }
      }
      _lastPollError = null;
    } on ApiException catch (error) {
      // Avoid showing the same offline error on every polling tick.
      if (_lastPollError != error.message) _notify(error.message);
      _lastPollError = error.message;
    } finally {
      _polling = false;
      if (_refreshQueued) unawaited(_poll());
    }
  }

  Future<void> _incoming(String id) async {
    if (!session.isSignedIn || _signedOut || _disposed) return;
    if (callState.value?.id == id) return;
    final userId = session.currentUser!.id;
    final generation = _generation;
    try {
      final call = await _api.getCall(id);
      if (!_sameSession(userId, generation)) return;
      await _presentIncoming(call);
    } on ApiException catch (error) {
      _notify(error.message);
    }
  }

  Future<void> _presentIncoming(CallSession call) async {
    if (_disposed || _signedOut) return;
    if (_pendingCallId == call.id) return;
    final userId = session.currentUser?.id;
    if (userId == null || !call.canAnswer(userId, _now())) {
      await _push.endCall(call.id);
      return;
    }
    if (_busy || callState.value != null) {
      if (callState.value?.id != call.id) {
        await _api.updateCall(call.id, 'decline');
        await _push.endCall(call.id);
      }
      return;
    }
    final navigator = navigatorKey.currentState;
    if (!_uiAvailable || navigator == null) {
      return; // Next poll retries once navigation is ready.
    }
    callState.value = call;
    _leaveFuture = null;
    final route = DialogRoute<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Incoming ${call.kind.name} call'),
          content: Text(
            call.isGroup
                ? '${call.callerName} is calling ${call.title}'
                : '${call.callerName} is calling',
          ),
          actions: [
            TextButton(
              onPressed: () => _decline(call.id),
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () => _accept(call.id),
              child: const Text('Answer'),
            ),
          ],
        ),
      ),
    );
    _incomingRoute = route;
    unawaited(navigator.push(route));
  }

  Future<void> _accept(String id) async {
    if (_busy || _disposed || _signedOut || !session.isSignedIn) return;
    if (_connection?.call.id == id || _media != null) return;
    if (callState.value != null && callState.value!.id != id) {
      _notify('Finish your current call first.');
      return;
    }
    _busy = true;
    _pendingCallId = id;
    _leaveFuture = null;
    final userId = session.currentUser!.id;
    final generation = _generation;
    try {
      await beforeConnect?.call();
      if (!_sameSession(userId, generation)) return;
      await _push.markAccepting(id);
      if (!_sameSession(userId, generation)) return;
      final connection = await _api.connectCall(id, accept: true);
      if (!_sameSession(userId, generation)) {
        if (!_signedOut && _api.isAuthenticated && session.currentUser?.id == userId) {
          await _api.updateCall(id, 'leave');
        }
        return;
      }
      _closeIncoming();
      _leaveFuture = null;
      await _beginMedia(connection);
    } on ApiException catch (error) {
      _notify(error.message);
      _closeIncoming();
      callState.value = null;
      await _push.endCall(id);
    } on PlatformException catch (error) {
      _notify('Cannot answer the system call: ${error.message ?? error.code}');
      await _leave();
      _closeIncoming();
    } catch (_) {
      _notify('Call media could not start. Check permissions and try again.');
      await _leave();
      _closeIncoming();
    } finally {
      if (_pendingCallId == id) _pendingCallId = null;
      _busy = false;
      if (_refreshQueued) unawaited(_poll());
    }
  }

  Future<void> _decline(String id) async {
    if (_disposed || _signedOut || !session.isSignedIn) return;
    if (_pendingCallId == id ||
        (_media != null && callState.value?.id == id)) {
      await _leave();
      return;
    }
    final claimedBusy = !_busy;
    if (claimedBusy) _busy = true;
    try {
      await _api.updateCall(id, 'decline');
      await _push.endCall(id);
      if (callState.value?.id == id) {
        _closeIncoming();
        callState.value = null;
      }
    } on ApiException catch (error) {
      _notify(error.message);
    } finally {
      if (claimedBusy) {
        _busy = false;
        if (_refreshQueued) unawaited(_poll());
      }
    }
  }

  void _closeIncoming() {
    final route = _incomingRoute;
    _incomingRoute = null;
    if (route != null && route.isActive) {
      navigatorKey.currentState?.removeRoute(route);
    }
  }

  Future<void> _beginMedia(CallConnection connection) async {
    if (_media != null) return;
    final id = connection.call.id;
    callState.value = connection.call;
    _connection = connection;
    _lastHeartbeat = _now();
    final initialMute = _muteStates[id] ?? await _push.getMuteState(id);
    if (_signedOut || _disposed || callState.value?.id != id || callState.value!.isEnded) return;
    final media = CallMediaSession(
      connection: connection,
      room: _roomFactory?.call(),
      initiallyMuted: _muteStates[id] ?? initialMute,
      prepareAudio: () => _push.prepareAudio(id),
      onConnected: () => _push.markConnected(id),
      onReady: () => _push.markMediaReady(id),
      onMuteChanged: (muted) => _push.setMuted(id, muted),
      onFailure: () async {
        _notify(_media?.error ?? 'Call media could not start.');
        await _leave();
      },
    );
    _media = media;
    _presentMedia();
    await media.start();
  }

  Future<void> _nativeMute(String id, bool muted) async {
    _muteStates[id] = muted;
    if (_media?.connection.call.id == id) {
      await _media!.setMuted(muted, fromNative: true);
    }
  }

  Future<void> _remoteEnded(String id) async {
    if (callState.value?.id != id && _pendingCallId != id) return;
    _generation++;
    _pendingCallId = null;
    if (callState.value?.id == id) {
      callState.value = callState.value!.endedLocally();
    }
    await _media?.stop();
    await _push.endCall(id);
    _closeIncoming();
    if (_callRoute == null) {
      _media = null;
      _connection = null;
      callState.value = null;
      _leaveFuture = null;
    }
  }

  void _presentMedia() {
    final connection = _connection;
    final media = _media;
    if (!_uiAvailable || _callRoute != null || connection == null || _media == null ||
        _media!.closing) {
      return;
    }
    final navigator = navigatorKey.currentState;
    final userId = session.currentUser?.id;
    if (navigator == null || userId == null || _signedOut) {
      // The same runtime will be rendered when the scene attaches. Never
      // disconnect an accepted call because no Flutter view exists yet.
      return;
    }
    _lastHeartbeat = _now();
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => CallScreen(
        connection: connection,
        currentUserId: userId,
        callState: callState,
        onLeave: _leave,
        prepareAudio: () => _push.prepareAudio(connection.call.id),
        onConnected: () => _push.markConnected(connection.call.id),
        media: media,
      ),
    );
    _callRoute = route;
    unawaited(navigator.push(route).then((_) async {
      await _leave();
      if (_disposed) return;
      _callRoute = null;
      _media = null;
      _connection = null;
      callState.value = null;
      _leaveFuture = null;
      _requestRefresh();
    }));
  }

  Future<void> _leave() => _leaveFuture ??= _leaveCurrent();

  Future<void> _leaveCurrent() async {
    final call = callState.value;
    final id = call?.id ?? _pendingCallId;
    if (id == null) return;
    _generation++;
    _pendingCallId = null;
    // Stop local media immediately, not after a possibly offline HTTP request.
    final stopping = _media?.stop();
    try {
      if (call?.isEnded != true && _api.isAuthenticated) {
        final updated = await _api.updateCall(id, 'leave');
        if (!_disposed) callState.value = updated;
      }
    } on ApiException catch (error) {
      _notify('Call stopped locally. ${error.message}');
    } finally {
      await _push.endCall(id);
      await stopping;
      // A group may remain active for everyone else after we leave.
      if (!_disposed && callState.value?.id == id) {
        callState.value = callState.value!.endedLocally();
      }
      if (_callRoute == null) {
        _media = null;
        _connection = null;
        callState.value = null;
      }
    }
  }

  Future<void> signOut() async {
    _generation++;
    _signedOut = true;
    _refreshQueued = false;
    _closeIncoming();
    final route = _callRoute;
    if (route != null && route.isActive) {
      navigatorKey.currentState?.removeRoute(route);
    }
    // Disable/journal-clear immediately, even if leave or token revocation is
    // offline. No new account may inherit a pending native call.
    final unregistering = _push.unregisterDevice();
    await _leave();
    callState.value = null;
    try {
      await unregistering;
    } on ApiException catch (error) {
      _notify('Could not unregister call notifications: ${error.message}');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _refreshQueued = false;
    _poller?.cancel();
    await _updates?.cancel();
    _updates = null;
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_sessionChanged);
    await _media?.stop();
    await _push.dispose();
  }
}
