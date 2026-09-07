import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';

import '../models/call_models.dart';

/// The only publisher for one accepted call. A Flutter view borrows this session;
/// attaching/detaching a scene never reconnects or disposes its Room.
class CallMediaSession extends ChangeNotifier with WidgetsBindingObserver {
  CallMediaSession({
    required this.connection,
    Room? room,
    this.prepareAudio,
    this.onConnected,
    this.onReady,
    this.onFailure,
    this.onMuteChanged,
    bool initiallyMuted = false,
  })  : room = room ??
            Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true)),
        _muted = initiallyMuted {
    this.room.addListener(_changed);
    _listener = this.room.createListener()
      ..on<RoomDisconnectedEvent>((event) {
        if (!_closing) _failed('Call disconnected. Please call again.');
      });
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
        (!kIsWeb && defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android);
  }

  final CallConnection connection;
  final Room room;
  final Future<void> Function()? prepareAudio;
  final Future<void> Function()? onConnected;
  final Future<void> Function()? onReady;
  final Future<void> Function()? onFailure;
  final Future<void> Function(bool muted)? onMuteChanged;
  late final EventsListener<RoomEvent> _listener;
  Future<void>? _starting;
  Future<void>? _stopping;
  Future<void> _muteWork = Future<void>.value();
  Future<void> _cameraWork = Future<void>.value();
  bool _muted;
  bool? _appliedMute;
  bool _closing = false;
  bool _failedOnce = false;
  bool _foreground = false;
  bool _cameraWanted = true;
  int _views = 0;
  String? error;
  DateTime? connectedAt;

  bool get muted => _muted;
  bool get closing => _closing;
  bool get connected => room.connectionState == ConnectionState.connected;
  bool get isVideo => connection.call.kind == CallKind.video;
  bool get hasView => _views > 0;

  Future<void> start() => _starting ??= _connect();

  Future<void> _connect() async {
    try {
      await prepareAudio?.call();
      if (_closing) return;
      await room.connect(connection.url, connection.token)
          .timeout(const Duration(seconds: 30));
      if (_closing) return;
      await onConnected?.call();
      if (_closing) return;
      await _applyMute();
      if (_closing) return;
      await _applyCamera();
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await AudioManager.instance.setSpeakerOutputPreferred(isVideo && hasView);
      }
      if (_closing) return;
      await onReady?.call();
      _changed();
    } catch (failure) {
      if (!_closing) _failed(_message(failure));
    }
  }

  String _message(Object failure) {
    if (failure is TimeoutException) {
      return 'Connection timed out. Check your internet connection.';
    }
    if (failure is PlatformException) {
      return 'Microphone or audio unavailable: ${failure.message ?? failure.code}';
    }
    if (failure is LiveKitException) {
      return 'Unable to connect: ${failure.message}';
    }
    if (failure is String) return 'Microphone or audio unavailable: $failure';
    return 'Call audio is not ready. Check permissions and try again.';
  }

  void _failed(String message) {
    if (_closing || _failedOnce) return;
    _failedOnce = true;
    error = message;
    notifyListeners();
    // Do not await stop from the connection future that stop itself must join.
    unawaited(Future<void>(() async {
      try {
        await onFailure?.call();
      } finally {
        await stop();
      }
    }));
  }

  void _changed() {
    if (_closing) return;
    if (connected && room.remoteParticipants.isNotEmpty) {
      connectedAt ??= DateTime.now();
    }
    notifyListeners();
  }

  /// Desired mute is updated synchronously, even while Room.connect is pending.
  Future<void> setMuted(bool muted, {bool fromNative = false}) async {
    if (_closing) return;
    final changed = _muted != muted;
    _muted = muted;
    notifyListeners();
    if (connected && _starting != null) {
      try {
        await _applyMute();
      } catch (_) {
        // Never display "muted" while a failed device operation leaves the
        // microphone live. Failing closed is preferable to unintended capture.
        _failed('Microphone control failed. The call has been stopped.');
        rethrow;
      }
    }
    if (!fromNative && changed && !_closing) {
      await onMuteChanged?.call(muted);
    }
  }

  Future<void> _applyMute() {
    _muteWork = _muteWork.catchError((Object _) {}).then((_) async {
      while (!_closing && connected && _appliedMute != _muted) {
        final target = _muted;
        await room.localParticipant!.setMicrophoneEnabled(!target);
        _appliedMute = target;
      }
      if (!_closing) notifyListeners();
    });
    return _muteWork;
  }

  void attachView() {
    _views++;
    if (connected && _starting != null) unawaited(_applyCamera());
  }

  void detachView() {
    if (_views > 0) _views--;
    if (connected && !_closing) unawaited(_applyCamera());
  }

  Future<void> setCamera(bool enabled) {
    _cameraWanted = enabled;
    return _applyCamera();
  }

  Future<void> _applyCamera() {
    _cameraWork = _cameraWork.catchError((Object _) {}).then((_) async {
      if (!isVideo || !connected || _closing) return;
      final enabled = _cameraWanted && hasView && _foreground;
      if (room.localParticipant?.isCameraEnabled() == enabled) return;
      try {
        await room.localParticipant!.setCameraEnabled(enabled);
      } catch (failure) {
        error = 'Camera unavailable; audio remains connected. ${_message(failure)}';
      }
      if (!_closing) notifyListeners();
    });
    return _cameraWork;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (connected && !_closing) unawaited(_applyCamera());
  }

  Future<void> stop() {
    if (_stopping != null) return _stopping!;
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    room.removeListener(_changed);
    notifyListeners();
    return _stopping = _stopRoom();
  }

  Future<void> _stopRoom() async {
    try {
      await _starting;
      await _muteWork.catchError((Object _) {});
      await _cameraWork.catchError((Object _) {});
    } finally {
      try {
        await room.disconnect();
      } finally {
        try {
          await _listener.dispose();
        } finally {
          await room.dispose();
        }
      }
    }
  }
}
