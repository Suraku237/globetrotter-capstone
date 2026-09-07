import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'api_service.dart';

bool get _nativeCalls =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
bool get _pushSupported => kIsWeb || _nativeCalls;
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
String? _callId(Object? value) {
  final id = value?.toString();
  return id != null && _uuid.hasMatch(id) ? id.toLowerCase() : null;
}

bool _validIncoming(Map<String, dynamic> data) {
  final expiry = DateTime.tryParse('${data['expires_at']}');
  return data['type'] == 'incoming_call' &&
      _callId(data['call_id']) != null &&
      (data['kind'] == 'voice' || data['kind'] == 'video') &&
      expiry != null &&
      expiry.isAfter(DateTime.now().toUtc());
}

Future<void> _endNative(String id) async {
  final prefs = await SharedPreferences.getInstance();
  // Also read by the native event journals to avoid end -> decline loops.
  await prefs.setBool('call_push_suppressed_$id', true);
  await prefs.remove('call_push_local_accept_$id');
  if (_nativeCalls) await FlutterCallkitIncoming.endCall(id);
}

Future<void> _showNative(Map<String, dynamic> data) async {
  if (!_nativeCalls || !_validIncoming(data)) return;
  final id = _callId(data['call_id'])!;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (prefs.getBool('call_push_enabled') != true ||
      prefs.getBool('call_push_suppressed_$id') == true ||
      prefs.getBool('call_push_local_accept_$id') == true ||
      prefs.getBool('call_push_shown_$id') == true) {
    return;
  }
  final calls = await FlutterCallkitIncoming.activeCalls();
  if (calls.any((call) => _callId(call.id) == id)) {
    return;
  }
  final duration = DateTime.parse('${data['expires_at']}')
      .difference(DateTime.now().toUtc())
      .inMilliseconds;
  if (duration <= 0) return;
  await prefs.reload();
  if (prefs.getBool('call_push_enabled') != true) return;
  await FlutterCallkitIncoming.showCallkitIncoming(
    CallKitParams(
      id: id,
      nameCaller: '${data['caller_name'] ?? 'GlobeTrotter caller'}',
      appName: 'GlobeTrotter',
      handle: data['kind'] == 'video' ? 'Video call' : 'Voice call',
      type: data['kind'] == 'video' ? 1 : 0,
      duration: duration,
      extra: data,
      missedCallNotification: const NotificationParams(showNotification: false),
      android: const AndroidParams(
        isCustomNotification: true,
        ringtonePath: 'system_ringtone_default',
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        supportsHolding: false,
        supportsDTMF: false,
        configureAudioSession: false,
        audioSessionActive: false,
      ),
    ),
  );
  await prefs.reload();
  if (prefs.getBool('call_push_enabled') != true) {
    await _endNative(id);
    return;
  }
  await prefs.setBool('call_push_shown_$id', true);
}

Future<void> _receiveCallEnded(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (prefs.getBool('call_push_enabled') != true) return;
  await prefs.setBool('call_push_reconcile_$id', true);
  if (prefs.getBool('call_push_local_accept_$id') == true) return;
  if (_nativeCalls) {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls.any((call) => _callId(call.id) == id && call.isAccepted)) {
      await prefs.setBool('call_push_local_accept_$id', true);
      return;
    }
  }
  // This push also means "answered on another installation", not necessarily
  // that the conversation ended. Only an unanswered ring can be dismissed now.
  await prefs.reload();
  if (prefs.getBool('call_push_local_accept_$id') == true) return;
  await _endNative(id);
}

@pragma('vm:entry-point')
Future<void> _callPushBackground(RemoteMessage message) async {
  if (!_nativeCalls) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  final id = _callId(message.data['call_id']);
  if (id == null) return;
  if (message.data['type'] == 'call_ended') {
    await _receiveCallEnded(id);
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    await _showNative(message.data);
  }
  // iOS incoming calls are reported immediately by PushKit, not by FCM.
}

/// Call after Firebase.initializeApp and before runApp.
Future<void> initializeCallPushBackground() async {
  if (_nativeCalls) {
    FirebaseMessaging.onBackgroundMessage(_callPushBackground);
  }
}

/// The owner must call registerDevice only after restoring authenticated state,
/// and unregisterDevice before clearing that state. Push never grants access.
class CallPushService with WidgetsBindingObserver {
  CallPushService({
    required this.onIncoming,
    required this.onAccept,
    required this.onDecline,
    required this.onError,
    this.onMuteChanged,
    this.onEnded,
  });

  final Future<void> Function(String callId) onIncoming;
  final Future<void> Function(String callId) onAccept;
  final Future<void> Function(String callId) onDecline;
  final void Function(String message) onError;
  final Future<void> Function(String callId, bool muted)? onMuteChanged;
  final Future<void> Function(String callId)? onEnded;
  final Map<String, bool> _muteStates = {};
  int _nativeRestoreDepth = 0;
  static const _channel = MethodChannel('globetrotter/call_push');
  static const _eventsKey = 'call_push_pending_events';
  static const _tokensKey = 'call_push_registered_tokens';
  static const _vapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<String> _delivered = {};
  final Set<String> _connectedNativeIds = {};
  final Map<String, String> _registered = {};
  Future<void> _work = Future<void>.value();
  Future<void>? _unregistration;
  bool _initialized = false;
  bool _authenticated = false;
  bool _disposed = false;
  int _authEpoch = 0;

  String get _platform => kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android';

  void _enqueue(Future<void> Function() action) {
    _work = _work.then((_) async {
      if (!_disposed) await action();
    }).catchError((Object _) {
      if (!_disposed) onError('Call notifications could not be updated.');
    });
  }

  Future<void> initialize() async {
    if (_initialized || _disposed || !_pushSupported) return;
    if (!await FirebaseMessaging.instance.isSupported()) {
      onError('This browser does not support background call notifications.');
      return;
    }
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final savedTokens = prefs.getString(_tokensKey);
    if (savedTokens != null) {
      _registered
          .addAll(Map<String, String>.from(jsonDecode(savedTokens) as Map));
    }
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(FirebaseMessaging.onMessage.listen(
      (message) => _enqueue(() => _message(message.data)),
    ));
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _enqueue(() => _message(message.data)),
    ));
    _subscriptions.add(FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => _enqueue(() async {
        if (_authenticated) await _registerToken(token, 'fcm');
      }),
    ));
    if (_nativeCalls) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'eventsAvailable' && _authenticated) {
          _enqueue(_restoreNativeEvents);
        } else if (call.method == 'callEnded') {
          final id = _callId(call.arguments);
          if (id != null) await _handleTerminalAction(id);
        } else if (call.method == 'callError' && call.arguments is String) {
          onError(call.arguments as String);
          if (_platform == 'ios') await _channel.invokeMethod<void>('takeError');
        }
      });
      if (_platform == 'ios') {
        final error = await _channel.invokeMethod<String>('takeError');
        if (error != null) onError(error);
      }
      _subscriptions.add(FlutterCallkitIncoming.onEvent.listen((event) {
        if (event == null) return;
        if (event is CallEventActionCallToggleMute) {
          unawaited(_handleNativeMute(event.id, event.isMuted).catchError(
            (Object _) => onError('The microphone mute setting could not be applied.'),
          ));
        } else if (event is CallEventActionCallDecline ||
            event is CallEventActionCallEnded ||
            event is CallEventActionCallTimeout) {
          // Never queue a hangup behind a pending answer/Room.connect.
          unawaited(_nativeEvent(event).catchError(
            (Object _) => onError('The system call action could not be completed.'),
          ));
        } else {
          _enqueue(() => _nativeEvent(event));
        }
      }));
    }
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) await _message(initial.data);
    // A web notification opens the incoming screen, never accepts the call.
    if (kIsWeb) {
      final id = _callId(Uri.base.queryParameters['call_id']);
      final expiry = DateTime.tryParse(
        Uri.base.queryParameters['call_expires_at'] ?? '',
      );
      if (id != null && expiry != null && expiry.isAfter(DateTime.now())) {
        await _record('incoming', id, expiresAt: expiry.toIso8601String());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _authenticated) {
      _enqueue(() async {
        await _restoreNativeEvents();
        if (_platform == 'ios' && _authenticated) {
          await _registerVoip();
          await _registerFcm();
        }
      });
    }
  }

  Future<void> _message(Map<String, dynamic> data) async {
    final id = _callId(data['call_id']);
    if (id == null) return;
    if (data['type'] == 'call_ended') {
      await _receiveCallEnded(id);
      if (_authenticated) await _reconcileCallUpdates();
      return;
    }
    if (!_validIncoming(data)) return;
    // PushKit owns the iOS system UI to avoid duplicate FCM/VoIP ringing.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _showNative(data);
    }
    await _record('incoming', id, expiresAt: '${data['expires_at']}');
  }

  Future<void> _nativeEvent(CallEvent event) async {
    if (event is CallEventActionDidUpdateDevicePushTokenVoip) {
      if (_authenticated) await _registerVoip();
      return;
    }
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        final id = _callId(callKitParams.id);
        if (id != null) await _record('accept', id);
      case CallEventActionCallDecline(:final callKitParams):
        final id = _callId(callKitParams.id);
        if (id != null) await _handleTerminalAction(id);
      case CallEventActionCallEnded(:final callKitParams):
        final id = _callId(callKitParams.id);
        if (id != null) await _handleTerminalAction(id);
      case CallEventActionCallTimeout(:final id):
        final validId = _callId(id);
        if (validId != null) await _handleTerminalAction(validId);
      case CallEventActionCallIncoming(:final callKitParams):
        final id = _callId(callKitParams.id);
        final data = callKitParams.extra;
        if (id != null && data != null) {
          if (_validIncoming(data)) {
            await _record('incoming', id, expiresAt: '${data['expires_at']}');
          }
        }
      default:
        break;
    }
  }

  Future<void> _record(String action, String id, {String? expiresAt, bool drain = true}) async {
    final epoch = _authEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (epoch != _authEpoch ||
        prefs.getBool('call_push_enabled') != true ||
        prefs.getBool('call_push_suppressed_$id') == true) {
      return;
    }
    if (action == 'accept') {
      await prefs.setBool('call_push_local_accept_$id', true);
    }
    final events = prefs.getStringList(_eventsKey) ?? [];
    final key = '$id:$action';
    if (!events.any((e) => (jsonDecode(e) as Map)['key'] == key)) {
      events.add(jsonEncode({
        'key': key,
        'id': id,
        'action': action,
        'expires_at': expiresAt,
      }));
      await prefs.setStringList(_eventsKey, events);
    }
    if (_authenticated && drain && _nativeRestoreDepth == 0) await _drain();
  }

  Future<void> _handleTerminalAction(String id) async {
    await _record('decline', id, drain: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final key = '$id:decline';
    if (!_authenticated || prefs.getBool('call_push_suppressed_$id') == true ||
        !_delivered.add(key)) {
      return;
    }
    try {
      await onDecline(id);
    } catch (_) {
      _delivered.remove(key);
      rethrow;
    }
  }

  Future<void> _handleNativeMute(String rawId, bool muted) async {
    final id = _callId(rawId);
    if (id == null || _disposed) return;
    _muteStates[id] = muted;
    final applying = _authenticated ? onMuteChanged?.call(id, muted) : null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('call_push_mute_$id', muted);
    await applying;
  }

  Future<bool> getMuteState(String callId) async {
    final id = _callId(callId);
    if (id == null) return false;
    if (_muteStates.containsKey(id)) return _muteStates[id]!;
    if (_nativeCalls) {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls.any((call) => _callId(call.id) == id)) {
        final muted = await FlutterCallkitIncoming.isMuted(id);
        _muteStates[id] = muted;
        return muted;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('call_push_mute_$id') ?? false;
  }

  Future<void> setMuted(String callId, bool muted) async {
    final id = _callId(callId);
    if (id == null || _disposed) return;
    _muteStates[id] = muted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('call_push_mute_$id', muted);
    if (!_nativeCalls || prefs.getBool('call_push_suppressed_$id') == true) return;
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls.any((call) => _callId(call.id) == id)) {
      await FlutterCallkitIncoming.muteCall(id, isMuted: muted);
    }
  }

  Future<void> _drain() async {
    if (!_authenticated || _disposed) return;
    final epoch = _authEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final events = prefs.getStringList(_eventsKey) ?? [];
    for (final encoded in List<String>.of(events)) {
      if (!_authenticated || _disposed || epoch != _authEpoch) break;
      final event = jsonDecode(encoded) as Map;
      final id = _callId(event['id']);
      final key = '${event['key']}';
      final action = event['action'];
      final expiry = DateTime.tryParse('${event['expires_at']}');
      final terminalQueued = events.any((other) {
        final value = jsonDecode(other) as Map;
        return value['id'] == id && value['action'] == 'decline';
      });
      if (id != null &&
          !_delivered.contains(key) &&
          prefs.getBool('call_push_suppressed_$id') != true) {
        if (action == 'decline') {
          await onDecline(id);
        } else if (action == 'accept' &&
            !terminalQueued &&
            !_delivered.contains('$id:decline')) {
          await onAccept(id);
        } else if (action == 'incoming' &&
            !terminalQueued &&
            !_delivered.contains('$id:decline') &&
            !_delivered.contains('$id:accept') &&
            expiry != null &&
            expiry.isAfter(DateTime.now())) {
          await onIncoming(id);
        }
        if (epoch != _authEpoch || !_authenticated) return;
        _delivered.add(key);
      }
      events.remove(encoded);
      await prefs.setStringList(_eventsKey, events);
    }
  }

  Future<void> _restoreNativeEvents() async {
    if (!_nativeCalls) {
      await _reconcileCallUpdates();
      await _drain();
      return;
    }
    final events =
        await _channel.invokeListMethod<dynamic>('pendingEvents') ?? [];
    // Copy the entire native journal before delivering, so end supersedes accept.
    final epoch = _authEpoch;
    _nativeRestoreDepth++;
    try {
      for (final value in events) {
        if (value is! Map) continue;
        final id = _callId(value['id']);
        if (id == null) continue;
        if (value['action'] == 'accept') {
          _muteStates[id] = await FlutterCallkitIncoming.isMuted(id);
        }
        await _record('${value['action']}', id, drain: false);
        if (epoch != _authEpoch) return;
        await _channel.invokeMethod<void>('ackEvent', value['key']);
      }
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls) {
        final id = _callId(call.id);
        if (id == null) continue;
        if (call.isAccepted) {
          _muteStates[id] = await FlutterCallkitIncoming.isMuted(id);
          await _record('accept', id, drain: false);
        } else if (call.extra != null) {
          final data = call.extra!;
          if (_validIncoming(data)) {
            await _record('incoming', id, expiresAt: '${data['expires_at']}', drain: false);
          } else {
            await _endNative(id);
          }
        }
      }
    } finally {
      _nativeRestoreDepth--;
    }
    if (epoch != _authEpoch || _nativeRestoreDepth != 0) return;
    await _reconcileCallUpdates();
    await _drain();
  }

  Future<void> _reconcileCallUpdates() async {
    if (!_authenticated || _disposed) return;
    final epoch = _authEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    const prefix = 'call_push_reconcile_';
    for (final key
        in prefs.getKeys().where((key) => key.startsWith(prefix)).toList()) {
      final id = _callId(key.substring(prefix.length));
      if (id == null) {
        await prefs.remove(key);
        continue;
      }
      if (epoch != _authEpoch || !_authenticated || _disposed) return;
      // getCall is the same authenticated, participant-scoped API used by the
      // coordinator. A cancellation hint must never act as a global hangup.
      try {
        final call = await ApiService.instance.getCall(id);
        if (epoch != _authEpoch || !_authenticated || _disposed) return;
        if (call.isEnded) {
          await endCall(id);
          await onEnded?.call(id);
        }
      } on ApiException catch (error) {
        if (error.statusCode != 403 && error.statusCode != 404) rethrow;
        if (epoch != _authEpoch || !_authenticated || _disposed) return;
        await endCall(id);
        await onEnded?.call(id);
      }
      await prefs.remove(key);
    }
  }

  Future<void> _registerToken(String token, String kind) async {
    if (token.isEmpty || !_authenticated) return;
    final epoch = _authEpoch;
    final old = _registered[kind];
    await ApiService.instance.registerCallDevice(
      token: token,
      platform: _platform,
      kind: kind,
    );
    if (!_authenticated || epoch != _authEpoch) return;
    _registered[kind] = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokensKey, jsonEncode(_registered));
    if (old != null && old != token) {
      await ApiService.instance.unregisterCallDevice(
        token: old,
        platform: _platform,
        kind: kind,
      );
    }
  }

  Future<void> _registerVoip() async {
    final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    if (token is String && token.isNotEmpty) {
      await _registerToken(token, 'voip');
    } else {
      final old = _registered['voip'];
      if (old != null) {
        await ApiService.instance.unregisterCallDevice(
          token: old,
          platform: 'ios',
          kind: 'voip',
        );
        _registered.remove('voip');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokensKey, jsonEncode(_registered));
      }
    }
  }

  Future<void> _registerFcm() async {
    if (!_authenticated || _disposed) return;
    final epoch = _authEpoch;
    if (_platform == 'ios') {
      // APNs registration can finish after the permission dialog. FCM cannot
      // mint its iOS token until this exists; refresh/resume will retry later.
      String? apnsToken;
      for (var attempt = 0; attempt < 4; attempt++) {
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null) break;
        if (epoch != _authEpoch || !_authenticated || _disposed) return;
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      if (apnsToken == null) {
        onError(
            'iOS background call updates are waiting for APNs registration. Check push configuration and reopen the app.');
        return;
      }
    }
    if (epoch != _authEpoch || !_authenticated || _disposed) return;
    if (kIsWeb && _vapidKey.isEmpty) {
      onError(
          'Web call notifications need FIREBASE_WEB_VAPID_KEY configuration.');
      return;
    }
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb ? _vapidKey : null,
    );
    if (token != null && epoch == _authEpoch) {
      await _registerToken(token, 'fcm');
    }
  }

  /// Restores authenticated native actions without any permission UI. Safe
  /// before runApp and during a scene-less iOS PushKit wake.
  Future<void> restoreSession() async {
    if (!_pushSupported || _disposed) return;
    await _unregistration;
    final epoch = ++_authEpoch;
    await initialize();
    if (!_initialized || epoch != _authEpoch || _disposed) return;
    _authenticated = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('call_push_enabled', true);
    if (_platform == 'ios') await _channel.invokeMethod<void>('setEnabled', true);
    await _restoreNativeEvents();
    if (epoch != _authEpoch || !_authenticated || _disposed) return;
    // Token refresh can wait; answering never depends on a registration POST.
    _enqueue(() async {
      if (!_authenticated) return;
      if (_platform == 'ios') await _registerVoip();
      final permission = await FirebaseMessaging.instance.getNotificationSettings();
      if (_platform == 'ios' ||
          permission.authorizationStatus == AuthorizationStatus.authorized ||
          permission.authorizationStatus == AuthorizationStatus.provisional) {
        await _registerFcm();
      }
    });
  }

  Future<void> registerDevice() async {
    if (!_pushSupported || _disposed) return;
    final epoch = ++_authEpoch;
    // Start the browser prompt directly inside the toolbar click's activation
    // window, before initialization, storage, native recovery or network work.
    final webPermission = kIsWeb
        ? await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
        : null;
    await _unregistration;
    if (_disposed || epoch != _authEpoch) return;
    await initialize();
    if (!_initialized || epoch != _authEpoch) return;
    _authenticated = true;
    final prefs = await SharedPreferences.getInstance();
    if (epoch != _authEpoch) return;
    await prefs.setBool('call_push_enabled', true);
    if (epoch != _authEpoch) return;
    if (_platform == 'ios') {
      await _channel.invokeMethod<void>('setEnabled', true);
    }
    // On mobile, recover accepted lock-screen calls before asking permissions.
    await _restoreNativeEvents();
    if (epoch != _authEpoch || !_authenticated) return;
    if (_platform == 'ios') await _registerVoip();
    if (epoch != _authEpoch || !_authenticated) return;
    final permission = webPermission ??
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
    if (epoch != _authEpoch || !_authenticated) return;
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      onError(
          'Enable notifications in system settings to receive call alerts.');
      // Silent APNs updates do not need alert consent. Keep an iOS FCM token
      // for call_ended even when the user denied ordinary notifications.
      if (_platform != 'ios') return;
    }
    if (_platform == 'android') {
      if (await FlutterCallkitIncoming.canUseFullScreenIntent() != true) {
        onError(
            'Allow full-screen call alerts in Android settings to ring on the lock screen.');
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    }
    await _registerFcm();
  }

  Future<void> unregisterDevice() async {
    if (_unregistration != null) return _unregistration;
    final operation = _unregisterDevice();
    _unregistration = operation;
    try {
      await operation;
    } finally {
      _unregistration = null;
    }
  }

  Future<void> _unregisterDevice() async {
    if (!_pushSupported) return;
    ++_authEpoch;
    _authenticated = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('call_push_enabled', false);
    await prefs.remove(_eventsKey);
    for (final key in prefs
        .getKeys()
        .where((key) => key.startsWith('call_push_reconcile_'))
        .toList()) {
      await prefs.remove(key);
    }
    _delivered.clear();
    _connectedNativeIds.clear();
    // Local delivery must be disabled before any potentially failing network
    // operation, including when a 401 already removed the API access token.
    if (_nativeCalls) {
      try {
        if (_platform == 'ios') {
          await _channel.invokeMethod<void>('setEnabled', false);
        }
        await _channel.invokeMethod<void>('clearEvents');
        final calls = await FlutterCallkitIncoming.activeCalls();
        for (final call in calls) {
          final id = _callId(call.id);
          if (id != null) await _endNative(id);
        }
      } catch (_) {
        onError('Could not dismiss the native call screen.');
      }
    }
    for (final entry in _registered.entries.toList()) {
      try {
        await ApiService.instance
            .unregisterCallDevice(
              token: entry.value,
              platform: _platform,
              kind: entry.key,
            )
            .timeout(const Duration(seconds: 5));
        _registered.remove(entry.key);
      } catch (_) {
        onError(
            'Could not unregister a call notification device. Retry when online.');
      }
    }
    await prefs.setString(_tokensKey, jsonEncode(_registered));
    if (_initialized) {
      try {
        await FirebaseMessaging.instance
            .deleteToken()
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        onError(
            'Could not revoke the old notification token; local call alerts remain disabled.');
      }
    }
  }

  Future<void> endCall(String callId) async {
    final id = _callId(callId);
    if (id == null || !_pushSupported) return;
    _connectedNativeIds.remove(id);
    await _endNative(id);
  }

  /// Call before submitting an in-app accept request. The backend sends
  /// call_ended to every installation of the accepting user to stop ringing.
  Future<void> markAccepting(String callId) async {
    final id = _callId(callId);
    if (id == null || !_pushSupported || _disposed || !_authenticated) return;
    final epoch = _authEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (epoch != _authEpoch ||
        !_authenticated ||
        prefs.getBool('call_push_enabled') != true ||
        prefs.getBool('call_push_suppressed_$id') == true) {
      return;
    }
    await prefs.setBool('call_push_local_accept_$id', true);
  }

  /// Call before Room.connect or creating local media, for incoming AND outgoing
  /// calls. CallKit owns iOS incoming activation; ordinary outgoing calls do not.
  Future<void> prepareAudio(String callId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final id = _callId(callId);
    if (id == null || _disposed || !_authenticated) {
      throw StateError('An authenticated call is required to prepare audio.');
    }
    final epoch = _authEpoch;
    final state =
        await _channel.invokeMapMethod<String, dynamic>('audioState') ?? {};
    final ids = state['callIds'] as List<dynamic>? ?? [];
    final usesCallKit = ids.any((value) => _callId(value) == id);
    if (!usesCallKit && (ids.isNotEmpty || state['active'] == true)) {
      throw StateError('Another system call currently owns the audio session.');
    }
    if (epoch != _authEpoch || !_authenticated || _disposed) {
      throw StateError('The authenticated call ended before audio was ready.');
    }
    // These are the LiveKit 2.11 APIs, not flutter_webrtc's legacy manual-audio
    // flag. The native delegate controls the actual ADM gate synchronously.
    // ignore: experimental_member_use
    await AudioManager.instance.setAudioSessionManagementMode(
      usesCallKit
          // ignore: experimental_member_use
          ? AudioSessionManagementMode.externalCallSystem
          // ignore: experimental_member_use
          : AudioSessionManagementMode.automatic,
    );
    if (epoch != _authEpoch || !_authenticated || _disposed) {
      throw StateError('The authenticated call ended before audio was ready.');
    }
    await _channel.invokeMethod<void>('syncAudioAvailability', {
      'callId': id,
      'usesCallKit': usesCallKit,
    });
  }

  /// Call only after authorized acceptance and a successful LiveKit connection.
  /// Outgoing calls without a native CallKit entry are intentionally a no-op.
  Future<void> markConnected(String callId) async {
    final id = _callId(callId);
    if (id == null ||
        !_nativeCalls ||
        _disposed ||
        !_authenticated ||
        _connectedNativeIds.contains(id)) {
      return;
    }
    final epoch = _authEpoch;
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (!calls.any((call) => _callId(call.id) == id)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (epoch != _authEpoch ||
        !_authenticated ||
        _disposed ||
        prefs.getBool('call_push_enabled') != true ||
        prefs.getBool('call_push_suppressed_$id') == true ||
        !_connectedNativeIds.add(id)) {
      return;
    }
    // iOS may emit another answer event while marking connected. It must not
    // re-enter the coordinator's accept flow for an already authorized call.
    _delivered.add('$id:accept');
    try {
      await FlutterCallkitIncoming.setCallConnected(id);
    } catch (_) {
      _connectedNativeIds.remove(id);
      rethrow;
    }

  }

  Future<void> markMediaReady(String callId) async {
    final id = _callId(callId);
    if (id != null && _platform == 'ios' && _authenticated && !_disposed) {
      await _channel.invokeMethod<void>('runtimeConnected', id);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _authenticated = false;
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    if (_nativeCalls) _channel.setMethodCallHandler(null);
    _connectedNativeIds.clear();
    await _work;
  }
}
