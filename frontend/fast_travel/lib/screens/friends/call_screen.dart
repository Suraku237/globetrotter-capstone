import 'dart:async' as async;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../Services/api_service.dart';
import 'package:fast_travel/Services/call_media_session.dart';
import '../../models/call_models.dart';
import '../../theme/app_theme.dart';

class CallScreen extends StatefulWidget {
  final CallConnection connection;
  final String currentUserId;
  final ValueListenable<CallSession?> callState;
  final Future<void> Function() onLeave;
  final Room? room;
  final Future<void> Function()? prepareAudio;
  final Future<void> Function()? onConnected;
  final CallMediaSession? media;

  const CallScreen({
    super.key,
    required this.connection,
    required this.currentUserId,
    required this.callState,
    required this.onLeave,
    this.room,
    this.prepareAudio,
    this.onConnected,
    this.media,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final Room _room;
  late final CallMediaSession _media;
  late final bool _ownsMedia;
  async.Timer? _clock;
  bool _busy = false;
  bool _leaving = false;
  bool _speakerOn = false;
  bool _frontCamera = true;
  String? _controlError;
  bool get _closing => _media.closing;
  String? get _error => _controlError ?? _media.error;
  DateTime? get _connectedAt => _media.connectedAt;

  bool get _video => widget.connection.call.kind == CallKind.video;
  bool get _ended => widget.callState.value?.isEnded ?? true;
  bool get _connected => _room.connectionState == ConnectionState.connected;
  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _ownsMedia = widget.media == null;
    _media = widget.media ??
        CallMediaSession(
          connection: widget.connection,
          room: widget.room,
          prepareAudio: widget.prepareAudio,
          onConnected: widget.onConnected,
          onFailure: widget.onLeave,
        );
    _room = _media.room;
    _speakerOn = _video || !_mobile;
    _media.addListener(_roomChanged);
    widget.callState.addListener(_callChanged);
    _media.attachView();
    if (_ownsMedia) async.unawaited(_media.start());
    _clock = async.Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connectedAt != null) setState(() {});
    });
  }

  void _showError(String message) {
    if (mounted && !_closing) setState(() => _controlError = message);
  }

  void _roomChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _callChanged() {
    if (!mounted) return;
    if (_ended) async.unawaited(_shutdown());
    setState(() {});
  }

  Future<void> _shutdown() => _media.stop();

  @override
  void dispose() {
    _clock?.cancel();
    _media.removeListener(_roomChanged);
    _media.detachView();
    widget.callState.removeListener(_callChanged);
    if (_ownsMedia) async.unawaited(_shutdown());
    super.dispose();
  }

  Future<void> _control(Future<void> Function() action) async {
    if (_busy || !_connected || _closing || _ended) return;
    setState(() => _busy = true);
    try {
      await action();
    } on LiveKitException catch (error) {
      _showError(error.message);
    } on PlatformException catch (error) {
      _showError(error.message ?? 'The device could not change this setting.');
    } on String catch (error) {
      _showError('Unable to change the media device: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setCamera(bool enabled) => _media.setCamera(enabled);

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    // Stop capture even if the backend is unreachable.
    final shutdown = _shutdown();
    await widget.onLeave();
    await shutdown;
    if (mounted) Navigator.of(context).pop();
  }

  String get _status {
    if (_ended) {
      return widget.callState.value?.endedReason?.replaceAll('_', ' ') ??
          'Call ended';
    }
    if (_room.connectionState == ConnectionState.reconnecting) {
      return 'Reconnecting...';
    }
    if (!_connected) return 'Connecting...';
    if (_room.remoteParticipants.isEmpty) {
      return _connectedAt == null
          ? 'Ringing...'
          : 'Waiting for participants...';
    }
    final elapsed = DateTime.now().difference(_connectedAt ?? DateTime.now());
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final local = _room.localParticipant;
    final remote = _room.remoteParticipants.values.toList();
    final enabled = _connected && !_busy && !_closing && !_ended;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) async.unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: AppColors.canopy,
        appBar: AppBar(
          backgroundColor: AppColors.canopy,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'End call and return',
            onPressed: _leaving ? null : _leave,
            icon: const Icon(Icons.expand_more),
          ),
          title: Text(widget.connection.call.title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(_video ? Icons.videocam : Icons.call),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Text(_status,
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.amberAccent)),
                ),
              if (kIsWeb && _connected && !_room.canPlaybackAudio && !_ended)
                FilledButton.icon(
                  onPressed: () => _control(_room.startAudio),
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Tap to hear the call'),
                ),
              Expanded(
                child: _ended || remote.isEmpty
                    ? Center(
                        child: _CallAvatar(
                          name: widget.connection.call.title,
                          url: widget.currentUserId ==
                                  widget.connection.call.callerId
                              ? null
                              : widget.connection.call.callerAvatarUrl,
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) => GridView.count(
                          padding: const EdgeInsets.all(12),
                          crossAxisCount: remote.length == 1
                              ? 1
                              : constraints.maxWidth > 700
                                  ? 3
                                  : 2,
                          childAspectRatio: remote.length == 1
                              ? constraints.maxWidth /
                                  constraints.maxHeight
                                      .clamp(1, double.infinity)
                              : 0.85,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          children: [
                            for (final participant in remote)
                              _ParticipantTile(
                                key: ValueKey(participant.identity),
                                participant: participant,
                                showVideo: _video,
                              ),
                          ],
                        ),
                      ),
              ),
              if (_video && local != null && !_ended && !_closing)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 110,
                      height: 145,
                      child: _ParticipantTile(
                        participant: local,
                        showVideo: true,
                        local: true,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    _button(
                      _media.muted ? Icons.mic_off : Icons.mic,
                      _media.muted ? 'Unmute' : 'Mute',
                      enabled
                          ? () => _control(() async {
                                await _media.setMuted(!_media.muted);
                              })
                          : null,
                    ),
                    if (_mobile)
                      _button(
                        _speakerOn ? Icons.volume_up : Icons.hearing,
                        _speakerOn ? 'Earpiece' : 'Speaker',
                        enabled
                            ? () => _control(() async {
                                  await AudioManager.instance
                                      .setSpeakerOutputPreferred(!_speakerOn);
                                  if (mounted) {
                                    setState(() => _speakerOn = !_speakerOn);
                                  }
                                })
                            : null,
                      ),
                    if (_video) ...[
                      _button(
                        local?.isCameraEnabled() == true
                            ? Icons.videocam
                            : Icons.videocam_off,
                        'Camera',
                        enabled
                            ? () => _control(
                                () => _setCamera(!local!.isCameraEnabled()))
                            : null,
                      ),
                      if (_mobile)
                        _button(
                          Icons.cameraswitch,
                          'Flip',
                          enabled && local?.isCameraEnabled() == true
                              ? () => _control(() async {
                                    final track = local!
                                        .videoTrackPublications.first.track;
                                    if (track == null) {
                                      throw TrackCreateException(
                                          'No camera track available');
                                    }
                                    await track.setCameraPosition(_frontCamera
                                        ? CameraPosition.back
                                        : CameraPosition.front);
                                    _frontCamera = !_frontCamera;
                                  })
                              : null,
                        ),
                    ],
                    _button(
                      Icons.call_end,
                      _ended ? 'Close' : 'Hang up',
                      _leaving ? null : _leave,
                      end: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(IconData icon, String label, VoidCallback? action,
      {bool end = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: label,
          onPressed: action,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: end ? Colors.red : Colors.white24,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white38,
            padding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final Participant participant;
  final bool showVideo;
  final bool local;

  const _ParticipantTile({
    super.key,
    required this.participant,
    required this.showVideo,
    this.local = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: participant,
      builder: (context, _) {
        VideoTrack? video;
        if (showVideo) {
          for (final publication in participant.videoTrackPublications) {
            final track = publication.track;
            if (track is VideoTrack && !publication.muted) {
              video = track;
              break;
            }
          }
        }
        final name = local
            ? 'You'
            : participant.name.isEmpty
                ? 'Participant'
                : participant.name;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ColoredBox(
            color: Colors.black26,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (video != null)
                  VideoTrackRenderer(video, fit: VideoViewFit.cover)
                else
                  Center(child: _CallAvatar(name: name, compact: local)),
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    color: Colors.black54,
                    child: Text(
                      '${participant.isMicrophoneEnabled() ? '' : 'Muted - '}$name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CallAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final bool compact;

  const _CallAvatar({required this.name, this.url, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = url;
    return CircleAvatar(
      radius: compact ? 28 : 54,
      backgroundColor: AppColors.ochre,
      foregroundColor: Colors.white,
      foregroundImage: avatarUrl == null
          ? null
          : NetworkImage(ApiService.resolveUrl(avatarUrl)),
      child: Text(
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
        style: TextStyle(fontSize: compact ? 22 : 38),
      ),
    );
  }
}
