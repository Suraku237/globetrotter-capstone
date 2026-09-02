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

// A small curated set rather than a full emoji keyboard package — covers
// the common "sticker" reactions without pulling in another dependency
// (and Unicode emoji render everywhere without shipping image assets).
const _kStickers = [
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

class ChatThreadScreen extends StatefulWidget {
  final SessionState session;
  final String conversationId;
  final ChatUser? otherUser;

  const ChatThreadScreen({
    super.key,
    required this.session,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  List<ChatMessage> _messages = [];
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
    // No websocket backend — a short poll keeps the thread reasonably
    // live without the complexity of standing up a second transport just
    // for chat, consistent with the rest of the app (feed, destinations,
    // etc. are all plain request/response too).
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
      final messages =
          await ApiService.instance.getMessages(widget.conversationId);
      if (!mounted) return;
      final grew = messages.length > _messages.length;
      setState(() => _messages = messages);
      if (initial || grew) {
        ApiService.instance.markConversationRead(widget.conversationId);
        _scrollToBottom(animated: !initial);
      }
    } catch (_) {
      // A missed poll isn't worth surfacing an error banner over — the
      // next one four seconds later will most likely succeed. Only the
      // very first load matters enough to show a spinner for.
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
      final message = await ApiService.instance
          .sendTextMessage(widget.conversationId, text);
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
      final message =
          await ApiService.instance.sendSticker(widget.conversationId, sticker);
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
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
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
    // On native platforms record needs a filesystem path to write to; on
    // web it manages capture internally and returns a blob URL from
    // stop() regardless of what's passed here.
    final path = audioTempPath('${DateTime.now().microsecondsSinceEpoch}.m4a');
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    setState(() => _recording = true);
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
      final message = await ApiService.instance
          .sendAudioMessage(widget.conversationId, bytes, 'voice.m4a');
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

  Future<void> _togglePlay(ChatMessage message) async {
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
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.sandDim,
              backgroundImage: widget.otherUser?.avatarUrl != null
                  ? NetworkImage(
                      ApiService.resolveUrl(widget.otherUser!.avatarUrl!))
                  : null,
              child: widget.otherUser?.avatarUrl == null
                  ? Text(
                      (widget.otherUser?.fullName.isNotEmpty ?? false)
                          ? widget.otherUser!.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.otherUser?.fullName ?? 'Traveler',
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
                      return _MessageBubble(
                        message: message,
                        mine: mine,
                        playing: _playingMessageId == message.id,
                        onPlayAudio: () => _togglePlay(message),
                      );
                    },
                  ),
          ),
          if (_showStickers) _StickerPicker(onPick: _sendSticker),
          _InputBar(
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

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final bool playing;
  final VoidCallback onPlayAudio;

  const _MessageBubble({
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

    Widget content;
    if (message.type == 'sticker') {
      // Stickers render as a bare, oversized emoji — no bubble chrome,
      // matching how sticker messages read in most chat apps.
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Text(message.sticker ?? '', style: const TextStyle(fontSize: 56)),
      );
      return Align(
        alignment: align,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
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
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
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
    );
  }
}

class _StickerPicker extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _StickerPicker({required this.onPick});

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
        itemCount: _kStickers.length,
        itemBuilder: (context, index) {
          final sticker = _kStickers[index];
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

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool recording;
  final VoidCallback onSend;
  final VoidCallback onToggleStickers;
  final VoidCallback onToggleRecording;

  const _InputBar({
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
                  hintText: recording ? 'Recording…' : 'Message',
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
