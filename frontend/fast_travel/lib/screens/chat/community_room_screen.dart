import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import 'audio_capture_web.dart' if (dart.library.io) 'audio_capture_io.dart';
import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

// Same curated sticker set as the 1:1 chat thread, kept in sync so the
// community room feels consistent with direct messages.
const _kRoomStickers = [
  '😀',
  '😂',
  '😍',
  '😎',
  '🥳',
  '😢',
  '😮',
  '😡',
  '👍',
  '👎',
  '🙏',
  '👏',
  '🎉',
  '❤️',
  '🔥',
  '✈️',
  '🗺️',
  '🏖️',
  '⛰️',
  '🌍',
  '📍',
  '🚗',
  '🍽️',
  '☀️',
];

/// A single public room every user can post text, emoji stickers, and
/// voice messages into — unlike ChatThreadScreen (a private 1:1 DM),
/// there's no conversation id or participant list to manage here.
class CommunityRoomScreen extends StatefulWidget {
  final SessionState session;

  const CommunityRoomScreen({super.key, required this.session});

  @override
  State<CommunityRoomScreen> createState() => _CommunityRoomScreenState();
}

class _CommunityRoomScreenState extends State<CommunityRoomScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  List<RoomMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _recording = false;
  bool _showStickers = false;
  String? _playingMessageId;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    // No websocket backend — a short poll keeps the room reasonably live,
    // consistent with how the 1:1 chat thread stays in sync.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingMessageId = null);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final messages = await ApiService.instance.getRoomMessages();
      if (!mounted) return;
      final grew = messages.length > _messages.length;
      setState(() => _messages = messages);
      if (initial || grew) _scrollToBottom(animated: !initial);
    } catch (_) {
      // A missed poll isn't worth surfacing an error banner over — the
      // next one four seconds later will most likely succeed.
    } finally {
      if (initial && mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(target,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;
    _textController.clear();
    setState(() => _sending = true);
    try {
      final message = await ApiService.instance.sendRoomText(text);
      if (!mounted) return;
      setState(() => _messages = [..._messages, message]);
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendSticker(String sticker) async {
    setState(() => _showStickers = false);
    try {
      final message = await ApiService.instance.sendRoomSticker(sticker);
      if (!mounted) return;
      setState(() => _messages = [..._messages, message]);
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recording) {
        final path = await _recorder.stop();
        if (mounted) setState(() => _recording = false);
        if (path == null) return;
        await _uploadRecording(path);
        return;
      }
      if (!await _recorder.hasPermission()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Microphone permission is needed to record a voice message.')),
        );
        return;
      }
      final path =
          audioTempPath('${DateTime.now().microsecondsSinceEpoch}.m4a');
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      if (mounted) setState(() => _recording = true);
    } on Object {
      if (!mounted) return;
      setState(() => _recording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not access the microphone.')),
      );
    }
  }

  Future<void> _uploadRecording(String path) async {
    setState(() => _sending = true);
    try {
      final Uint8List bytes;
      if (kIsWeb) {
        final res = await http.get(Uri.parse(path));
        bytes = res.bodyBytes;
      } else {
        bytes = await readAudioBytes(path);
      }
      final message = await ApiService.instance.sendRoomAudio(bytes, 'voice.m4a');
      if (!mounted) return;
      setState(() => _messages = [..._messages, message]);
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the voice message.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _togglePlay(RoomMessage message) async {
    if (message.audioUrl == null) return;
    if (_playingMessageId == message.id) {
      await _player.pause();
      setState(() => _playingMessageId = null);
      return;
    }
    await _player.play(UrlSource(ApiService.resolveUrl(message.audioUrl!)));
    setState(() => _playingMessageId = message.id);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.session.currentUser?.id ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.public_rounded),
            SizedBox(width: 10),
            Text('Community Room'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.ochre))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final mine = message.senderId == currentUserId;
                      return _RoomMessageBubble(
                        message: message,
                        mine: mine,
                        playing: _playingMessageId == message.id,
                        onPlayAudio: () => _togglePlay(message),
                      );
                    },
                  ),
          ),
          if (_showStickers) _RoomStickerPicker(onPick: _sendSticker),
          _RoomInputBar(
            controller: _textController,
            sending: _sending,
            recording: _recording,
            onSend: _sendText,
            onToggleStickers: () =>
                setState(() => _showStickers = !_showStickers),
            onToggleRecording: _toggleRecording,
          ),
        ],
      ),
    );
  }
}

class _RoomMessageBubble extends StatelessWidget {
  final RoomMessage message;
  final bool mine;
  final bool playing;
  final VoidCallback onPlayAudio;

  const _RoomMessageBubble({
    required this.message,
    required this.mine,
    required this.playing,
    required this.onPlayAudio,
  });

  @override
  Widget build(BuildContext context) {
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = mine ? AppColors.ochre : AppColors.sandDim;
    final textColor = mine ? Colors.white : AppColors.ink;

    // Everyone posts into the same thread, so (unlike a 1:1 DM) each
    // bubble needs to show who sent it.
    Widget senderLabel = Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
      child: Text(
        mine ? 'You' : message.senderName,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft),
      ),
    );

    Widget content;
    if (message.type == 'sticker') {
      content = Text(message.sticker ?? '', style: const TextStyle(fontSize: 56));
      return Align(
        alignment: align,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [senderLabel, content],
          ),
        ),
      );
    }

    if (message.type == 'audio') {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
                playing
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                color: textColor,
                size: 32),
            onPressed: onPlayAudio,
          ),
          Icon(Icons.graphic_eq_rounded,
              color: textColor.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Text('Voice message', style: TextStyle(color: textColor)),
        ],
      );
    } else {
      content = Text(message.text ?? '',
          style: TextStyle(color: textColor, fontSize: 15));
    }

    return Align(
      alignment: align,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          senderLabel,
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
            ),
            child: content,
          ),
        ],
      ),
    );
  }
}

class _RoomStickerPicker extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _RoomStickerPicker({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: AppColors.sandDim,
        border: Border(top: BorderSide(color: Color(0x1A16181D))),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
        ),
        itemCount: _kRoomStickers.length,
        itemBuilder: (context, index) {
          final sticker = _kRoomStickers[index];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onPick(sticker),
            child: Center(
                child: Text(sticker, style: const TextStyle(fontSize: 28))),
          );
        },
      ),
    );
  }
}

class _RoomInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool recording;
  final VoidCallback onSend;
  final VoidCallback onToggleStickers;
  final VoidCallback onToggleRecording;

  const _RoomInputBar({
    required this.controller,
    required this.sending,
    required this.recording,
    required this.onSend,
    required this.onToggleStickers,
    required this.onToggleRecording,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined),
              color: AppColors.inkSoft,
              onPressed: onToggleStickers,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                enabled: !recording,
                decoration: InputDecoration(
                  hintText: recording ? 'Recording…' : 'Message everyone',
                  filled: true,
                  fillColor: AppColors.sandDim,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 4),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                if (hasText) {
                  return IconButton(
                    icon: const Icon(Icons.send_rounded),
                    color: AppColors.ochre,
                    onPressed: sending ? null : onSend,
                  );
                }
                return IconButton(
                  icon: Icon(recording
                      ? Icons.stop_circle_rounded
                      : Icons.mic_rounded),
                  color: recording ? AppColors.clay : AppColors.inkSoft,
                  onPressed: sending ? null : onToggleRecording,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
