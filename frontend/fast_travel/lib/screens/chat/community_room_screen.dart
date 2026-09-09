import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../../Services/api_service.dart';
import '../../Services/media_cache.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import 'audio_capture_web.dart' if (dart.library.io) 'audio_capture_io.dart';
import 'chat_ui.dart';

// Curated sticker set — same list as before, kept small so the picker
// stays a quick emoji pad rather than a full keyboard.
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

// Quick-react options offered by the long-press menu. Deliberately just
// the six WhatsApp/iMessage-standard reactions — a full picker would be
// out of scope and rarely used.
const _kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// One public conversation for everyone signed in, alongside private chats.
class CommunityRoomScreen extends StatefulWidget {
  final SessionState session;

  const CommunityRoomScreen({super.key, required this.session});

  @override
  State<CommunityRoomScreen> createState() => _CommunityRoomScreenState();
}

class _CommunityRoomScreenState extends State<CommunityRoomScreen> {
  final _textController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  AudioPlayer? _player;
  StreamSubscription<void>? _playerComplete;
  final _imagePicker = ImagePicker();

  List<RoomMessage> _messages = [];
  String? _oldestCursor;
  RoomPresence _presence = const RoomPresence(count: 0, users: []);
  bool _loading = true;
  bool _sending = false;
  bool _recording = false;
  bool _showStickers = false;
  bool _searchOpen = false;
  String _searchQuery = '';
  String? _playingMessageId;
  RoomMessage? _replyingTo;
  late final ChatRefreshController _updates;
  Timer? _heartbeatTimer;
  bool _heartbeatInFlight = false;
  DateTime? _lastPresenceRead;
  bool _loadingOlder = false;
  bool _historyLoaded = false;
  bool _canLoadOlder = false;
  bool _hasNewMessages = false;
  String? _loadError;
  String? _sendError;
  Future<void> Function()? _retrySend;

  @override
  void initState() {
    super.initState();
    _updates = ChatRefreshController(
      changes: ApiService.instance.changes,
      topics: const {'chat'},
      isLive: () => ApiService.instance.isLive,
      isVisible: () =>
          mounted &&
          TickerMode.of(context) &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      load: _load,
      invalidate: ApiService.instance.refreshTopics,
      onResume: () => _sendHeartbeat(),
    )..start();
    // The server prunes stale entries after ~15 s, so a 5 s heartbeat
    // keeps this viewer in the "active now" list without spamming.
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sendHeartbeat(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendHeartbeat());
    _scrollController.addListener(() {
      if (_hasNewMessages && _nearBottom) {
        setState(() => _hasNewMessages = false);
      }
    });
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q == _searchQuery) return;
      setState(() => _searchQuery = q);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updates.visibilityChanged();
  }

  @override
  void dispose() {
    _updates.dispose();
    _heartbeatTimer?.cancel();
    _textController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _playerComplete?.cancel();
    _player?.dispose();
    super.dispose();
  }

  // ---- Data ---------------------------------------------------------------

  bool get _nearBottom =>
      !_scrollController.hasClients ||
      _scrollController.position.extentAfter < 96;

  List<RoomMessage> _merge(Iterable<RoomMessage> incoming) =>
      mergeChatMessages(_messages, incoming,
          id: (message) => message.id,
          createdAt: (message) => message.createdAt);

  Future<void> _load() async {
    if (_loadingOlder) return;
    final initial = _loading;
    try {
      final messages = await ApiService.instance.getRoomMessages(limit: 50);
      if (!mounted) return;
      final ids = _messages.map((message) => message.id).toSet();
      final grew = messages.any((message) => !ids.contains(message.id));
      final follow = _searchQuery.isEmpty && (initial || _nearBottom);
      setState(() {
        _messages = _merge(messages);
        if (messages.isNotEmpty) _oldestCursor ??= messages.first.id;
        _loadError = null;
        if (!_historyLoaded) _canLoadOlder = messages.length >= 50;
        if (grew && !follow) _hasNewMessages = true;
      });
      if (follow && (initial || grew)) _scrollToBottom(animated: !initial);
    } on ApiException {
      if (mounted) {
        setState(() => _loadError = chatLabel(
            context,
            'Could not refresh. Your messages are still here.',
            'Actualisation impossible. Vos messages restent disponibles.'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_canLoadOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      await _updates.refresh();
      if (!mounted || !_canLoadOlder) return;
      final older = await ApiService.instance
          .getRoomMessages(before: _oldestCursor, limit: 50);
      if (!mounted) return;
      final position = _scrollController.hasClients
          ? _scrollController.position.pixels
          : 0.0;
      final extent = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;
      setState(() {
        _messages = mergeChatMessages(older, _messages,
            id: (message) => message.id,
            createdAt: (message) => message.createdAt);
        if (older.isNotEmpty) _oldestCursor = older.first.id;
        _historyLoaded = true;
        _canLoadOlder = older.length >= 50;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final current = _scrollController.position;
        _scrollController.jumpTo((position + current.maxScrollExtent - extent)
            .clamp(0.0, current.maxScrollExtent));
      });
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(chatLabel(context, 'Could not load older messages.',
              'Impossible de charger les anciens messages.')),
          action: SnackBarAction(
              label: chatLabel(context, 'Retry', 'Réessayer'),
              onPressed: _loadOlder),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingOlder = false);
        unawaited(_updates.refresh());
      }
    }
  }

  Future<void> _sendHeartbeat() async {
    if (_heartbeatInFlight || !_updates.active) return;
    _heartbeatInFlight = true;
    try {
      await ApiService.instance.roomHeartbeat();
      if (_lastPresenceRead == null ||
          DateTime.now().difference(_lastPresenceRead!).inSeconds >= 15) {
        final presence = await ApiService.instance.getRoomPresence();
        if (!mounted) return;
        _lastPresenceRead = DateTime.now();
        setState(() => _presence = presence);
      }
    } catch (_) {
      // Presence is best-effort and must not hide cached messages.
    } finally {
      _heartbeatInFlight = false;
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(target,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  // ---- Sending ------------------------------------------------------------

  void _startReply(RoomMessage message) {
    setState(() => _replyingTo = message);
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _sendText() async {
    final draft = _textController.text;
    if (draft.trim().isEmpty || _sending || _recording) return;
    final reply = _replyingTo;
    await _sendMessage(
      () =>
          ApiService.instance.sendRoomText(draft.trim(), replyToId: reply?.id),
      draft: draft,
      reply: reply,
      retry: _sendText,
    );
  }

  Future<void> _sendMessage(
    Future<RoomMessage> Function() send, {
    String? draft,
    RoomMessage? reply,
    Future<void> Function()? retry,
  }) async {
    if (_sending || !mounted) return;
    setState(() {
      _sending = true;
      _sendError = null;
      _retrySend = null;
    });
    try {
      final message = await send();
      if (!mounted) return;
      setState(() {
        _messages = _merge([message]);
        if (draft != null && _textController.text == draft) {
          _textController.clear();
        }
        if (_replyingTo?.id == reply?.id) _replyingTo = null;
        _hasNewMessages = false;
      });
      _scrollToBottom();
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _sendError = chatLabel(
            context,
            'Send not confirmed. Your draft is kept. Check the chat before retrying.',
            'Envoi non confirmé. Brouillon conservé. Vérifiez la discussion avant de réessayer.');
        _retrySend =
            retry ?? () => _sendMessage(send, draft: draft, reply: reply);
      });
      unawaited(_updates.refreshFromNetwork());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retryFailedSend() async {
    final retry = _retrySend;
    if (retry == null || _sending) return;
    if (await confirmChatRetry(context) && mounted) await retry();
  }

  Future<void> _sendSticker(String sticker) async {
    if (_sending || _recording) return;
    final reply = _replyingTo;
    setState(() => _showStickers = false);
    await _sendMessage(
      () => ApiService.instance.sendRoomSticker(sticker, replyToId: reply?.id),
      reply: reply,
    );
  }

  Future<void> _toggleRecording() async {
    if (_sending) return;
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
                'Microphone permission is needed to record a voice message.'),
          ),
        );
        return;
      }
      final path =
          audioTempPath('${DateTime.now().microsecondsSinceEpoch}.m4a');
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _recording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not access the microphone.')),
      );
    }
  }

  Future<void> _uploadRecording(String path) async {
    final reply = _replyingTo;
    await _sendMessage(() async {
      final Uint8List bytes;
      if (kIsWeb) {
        final res = await http.get(Uri.parse(path));
        bytes = res.bodyBytes;
      } else {
        bytes = await readAudioBytes(path);
      }
      return ApiService.instance
          .sendRoomAudio(bytes, 'voice.m4a', replyToId: reply?.id);
    }, reply: reply);
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_sending || _recording) return;
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file == null || !mounted) return;
      final draft = _textController.text;
      final reply = _replyingTo;
      await _sendMessage(() async {
        final bytes = await file.readAsBytes();
        return ApiService.instance.sendRoomImage(
          bytes,
          file.name.isNotEmpty ? file.name : 'photo.jpg',
          caption: draft.trim().isEmpty ? null : draft.trim(),
          replyToId: reply?.id,
        );
      }, draft: draft, reply: reply);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the photo.')),
      );
    }
  }

  // ---- Reactions / delete / copy -----------------------------------------

  Future<void> _toggleReaction(RoomMessage message, String emoji) async {
    try {
      final updated =
          await ApiService.instance.toggleRoomReaction(message.id, emoji);
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m.id == updated.id ? updated : m)
            .toList(growable: false);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteMessage(RoomMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
            'This removes it for everyone in the room and can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.clay)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final updated = await ApiService.instance.deleteRoomMessage(message.id);
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m.id == updated.id ? updated : m)
            .toList(growable: false);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _copyMessageText(RoomMessage message) async {
    final text = message.type == 'text'
        ? (message.text ?? '')
        : message.type == 'sticker'
            ? (message.sticker ?? '')
            : message.type == 'image'
                ? (message.text ?? '')
                : '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _showMessageActions(RoomMessage message) async {
    final mine = message.senderId == widget.session.currentUser?.id;
    final isAdmin = widget.session.currentUser?.role == 'admin';
    final canCopy =
        (message.type == 'text' && (message.text ?? '').isNotEmpty) ||
            (message.type == 'sticker') ||
            (message.type == 'image' && (message.text ?? '').isNotEmpty);
    if (message.deleted) return; // no menu on tombstones
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.sand,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _QuickReactionRow(
                  message: message,
                  currentUserId: widget.session.currentUser?.id ?? '',
                  onPick: (emoji) {
                    Navigator.pop(sheetCtx);
                    _toggleReaction(message, emoji);
                  },
                ),
              ),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _startReply(message);
                },
              ),
              if (canCopy)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _copyMessageText(message);
                  },
                ),
              if (mine || isAdmin)
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: AppColors.clay),
                  title: const Text('Delete for everyone',
                      style: TextStyle(color: AppColors.clay)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _deleteMessage(message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _togglePlay(RoomMessage message) async {
    if (message.audioUrl == null) return;
    try {
      if (_player == null) {
        _player = AudioPlayer();
        _playerComplete = _player!.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _playingMessageId = null);
        });
      }
      if (_playingMessageId == message.id) {
        await _player!.pause();
        if (mounted) setState(() => _playingMessageId = null);
        return;
      }
      await _player!.play(UrlSource(ApiService.resolveUrl(message.audioUrl!)));
      if (mounted) setState(() => _playingMessageId = message.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(chatLabel(context, 'Could not play this voice message.',
            'Impossible de lire ce message vocal.')),
      ));
    }
  }

  // ---- Filtering ----------------------------------------------------------

  List<RoomMessage> get _visibleMessages {
    if (_searchQuery.isEmpty) return _messages;
    final needle = _searchQuery.toLowerCase();
    return _messages.where((m) {
      if (m.deleted) return false;
      final haystack = <String>[
        m.senderName,
        m.text ?? '',
        m.sticker ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(needle);
    }).toList();
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.session.currentUser?.id ?? '';
    final visible = _visibleMessages;
    return Scaffold(
      backgroundColor: ChatColors.background,
      appBar: AppBar(
        backgroundColor: ChatColors.header,
        foregroundColor: Colors.white,
        title: _PresenceTitle(presence: _presence),
        actions: [
          IconButton(
            tooltip: chatLabel(
                context, 'Refresh messages', 'Actualiser les messages'),
            onPressed: _updates.refreshFromNetwork,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Search messages',
            icon:
                Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _searchController.clear();
                }
              });
            },
          ),
        ],
        bottom: _searchOpen
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: _RoomSearchBar(controller: _searchController),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          if (_loadError != null)
            ChatNotice(message: _loadError!, onRetry: _updates.refreshFromNetwork),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.ochre))
                : visible.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'Say hi to the community 👋'
                              : 'No messages match "$_searchQuery"',
                          style: const TextStyle(color: AppColors.inkSoft),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        findChildIndexCallback: (key) {
                          if (key is! ValueKey<String>) return null;
                          final index = visible
                              .indexWhere((message) => message.id == key.value);
                          return index < 0 ? null : index + 1;
                        },
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 16),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: visible.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            if (_searchQuery.isNotEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Center(
                              child: _loadingOlder
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    )
                                  : _canLoadOlder
                                      ? TextButton.icon(
                                          onPressed: _loadOlder,
                                          icon: const Icon(
                                              Icons.history_rounded,
                                              size: 18),
                                          label: Text(chatLabel(
                                              context,
                                              'Load older messages',
                                              'Charger les anciens messages')),
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(
                                              chatLabel(
                                                  context,
                                                  'Beginning of the conversation',
                                                  'Début de la discussion'),
                                              style: const TextStyle(
                                                  color: ChatColors.muted,
                                                  fontSize: 12)),
                                        ),
                            );
                          }
                          final messageIndex = index - 1;
                          final message = visible[messageIndex];
                          final mine = message.senderId == currentUserId;
                          // Group consecutive messages from the same
                          // sender within 5 minutes so the sender name +
                          // avatar only render on the first bubble of a
                          // run — cuts down the visual noise a lot,
                          // matching WhatsApp/Telegram.
                          final prev = messageIndex > 0
                              ? visible[messageIndex - 1]
                              : null;
                          final showSenderHeader =
                              prev == null || !_sameGroup(prev, message);
                          return Column(
                            key: ValueKey(message.id),
                            children: [
                              if (startsChatDay(
                                  prev?.createdAt, message.createdAt))
                                ChatDateSeparator(timestamp: message.createdAt),
                              _RoomMessageBubble(
                                message: message,
                                mine: mine,
                                currentUserId: currentUserId,
                                playing: _playingMessageId == message.id,
                                showSenderHeader: showSenderHeader,
                                highlight: _searchQuery.isNotEmpty
                                    ? _searchQuery
                                    : null,
                                onLongPress: () => _showMessageActions(message),
                                onSwipeReply: () => _startReply(message),
                                onPlayAudio: () => _togglePlay(message),
                                onQuickReact: (emoji) =>
                                    _toggleReaction(message, emoji),
                                onTapReply: () {
                                  // Scroll to the parent message if we can
                                  // find it — a small QoL touch that makes
                                  // long threads navigable.
                                  final targetId = message.replyTo?.id;
                                  if (targetId == null) return;
                                  final idx = visible
                                      .indexWhere((m) => m.id == targetId);
                                  if (idx < 0 ||
                                      !_scrollController.hasClients) {
                                    return;
                                  }
                                  _scrollController.animateTo(
                                    (idx *
                                            (_scrollController
                                                    .position.maxScrollExtent /
                                                visible.length))
                                        .clamp(
                                            0.0,
                                            _scrollController
                                                .position.maxScrollExtent),
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOut,
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
          ),
          if (_hasNewMessages)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _hasNewMessages = false;
                    });
                    _scrollToBottom();
                  },
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  label: Text(
                      chatLabel(context, 'New messages', 'Nouveaux messages')),
                ),
              ),
            ),
          if (_sendError != null)
            ChatNotice(
              message: _sendError!,
              onRetry: _sending ? null : _retryFailedSend,
              onDismiss: () => setState(() {
                _sendError = null;
                _retrySend = null;
              }),
            ),
          if (_showStickers) _RoomStickerPicker(onPick: _sendSticker),
          if (_replyingTo != null)
            _ReplyComposerPreview(
              message: _replyingTo!,
              onCancel: _cancelReply,
            ),
          ColoredBox(
            color: Colors.white,
            child: _RoomInputBar(
              controller: _textController,
              sending: _sending,
              recording: _recording,
              replying: _replyingTo != null,
              onSend: _sendText,
              onToggleStickers: () =>
                  setState(() => _showStickers = !_showStickers),
              onToggleRecording: _toggleRecording,
              onPickImage: () => _pickAndSendImage(ImageSource.gallery),
              onTakePhoto: () => _pickAndSendImage(ImageSource.camera),
            ),
          ),
        ],
      ),
    );
  }

  bool _sameGroup(RoomMessage a, RoomMessage b) {
    return a.senderId == b.senderId && sameChatRun(a.createdAt, b.createdAt);
  }
}

// ---- App-bar presence title -----------------------------------------------

class _PresenceTitle extends StatelessWidget {
  final RoomPresence presence;
  const _PresenceTitle({required this.presence});

  @override
  Widget build(BuildContext context) {
    final subtitle = presence.count == 0
        ? chatLabel(
            context, 'Public · everyone signed in', 'Public · tous les membres')
        : chatLabel(context, 'Public · ${presence.count} active now',
            'Public · ${presence.count} en ligne');
    return Row(
      children: [
        const CircleAvatar(
          backgroundColor: Color(0xFF7199B8),
          radius: 18,
          child: Icon(Icons.public_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(chatLabel(context, 'Community', 'Communauté'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- Search bar (shown when the app-bar search icon is toggled) ----------

class _RoomSearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _RoomSearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sandDim,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const Icon(Icons.search_rounded,
                  size: 18, color: AppColors.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search messages, senders…',
                    isCollapsed: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (value.text.isNotEmpty)
                GestureDetector(
                  onTap: controller.clear,
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.inkSoft),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---- Message bubble --------------------------------------------------------

class _RoomMessageBubble extends StatelessWidget {
  final RoomMessage message;
  final bool mine;
  final String currentUserId;
  final bool playing;
  final bool showSenderHeader;
  final String? highlight;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeReply;
  final VoidCallback onPlayAudio;
  final VoidCallback onTapReply;
  final ValueChanged<String> onQuickReact;

  const _RoomMessageBubble({
    required this.message,
    required this.mine,
    required this.currentUserId,
    required this.playing,
    required this.showSenderHeader,
    required this.highlight,
    required this.onLongPress,
    required this.onSwipeReply,
    required this.onPlayAudio,
    required this.onTapReply,
    required this.onQuickReact,
  });

  @override
  Widget build(BuildContext context) {
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        // Swipe right on a message to start a reply, matching WhatsApp.
        // Using onHorizontalDragEnd rather than a Dismissible so the row
        // itself doesn't animate away.
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 200) onSwipeReply();
        },
        onLongPress: onLongPress,
        onDoubleTap: message.deleted ? null : () => onQuickReact('❤️'),
        child: Column(
          crossAxisAlignment: align,
          children: [
            if (showSenderHeader)
              Padding(
                padding: EdgeInsets.only(
                    top: 6,
                    bottom: 2,
                    left: mine ? 0 : 44,
                    right: mine ? 4 : 0),
                child: Text(
                  mine ? 'You' : message.senderName,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft),
                ),
              ),
            Row(
              mainAxisAlignment:
                  mine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!mine && showSenderHeader)
                  _Avatar(
                    name: message.senderName,
                    url: message.senderAvatar,
                  )
                else if (!mine)
                  const SizedBox(width: 40),
                if (!mine) const SizedBox(width: 4),
                Flexible(
                  child: _BubbleContent(
                    message: message,
                    mine: mine,
                    playing: playing,
                    highlight: highlight,
                    onPlayAudio: onPlayAudio,
                    onTapReply: onTapReply,
                  ),
                ),
              ],
            ),
            if (message.reactions.isNotEmpty && !message.deleted)
              Padding(
                padding: EdgeInsets.only(
                    top: 4, left: mine ? 0 : 44, right: mine ? 4 : 0),
                child: _ReactionRow(
                  reactions: message.reactions,
                  currentUserId: currentUserId,
                  onTap: onQuickReact,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BubbleContent extends StatelessWidget {
  final RoomMessage message;
  final bool mine;
  final bool playing;
  final String? highlight;
  final VoidCallback onPlayAudio;
  final VoidCallback onTapReply;

  const _BubbleContent({
    required this.message,
    required this.mine,
    required this.playing,
    required this.highlight,
    required this.onPlayAudio,
    required this.onTapReply,
  });

  @override
  Widget build(BuildContext context) {
    // Stickers rendered without a bubble background for the classic
    // "big emoji" look.
    if (message.type == 'sticker' && !message.deleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.replyTo != null)
              _ReplyPreviewInsideBubble(
                reply: message.replyTo!,
                onTap: onTapReply,
                dark: false,
              ),
            Text(message.sticker ?? '', style: const TextStyle(fontSize: 56)),
            _TimestampLabel(createdAt: message.createdAt),
          ],
        ),
      );
    }

    final bg = message.deleted
        ? AppColors.sandDim
        : mine
            ? ChatColors.outgoing
            : Colors.white;
    final fg = message.deleted ? AppColors.inkSoft : ChatColors.ink;
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
      padding: message.type == 'image' && !message.deleted
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.replyTo != null && !message.deleted)
            _ReplyPreviewInsideBubble(
              reply: message.replyTo!,
              onTap: onTapReply,
              dark: false,
            ),
          if (message.deleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded, size: 14, color: fg),
                const SizedBox(width: 6),
                Text('This message was deleted',
                    style: TextStyle(
                        fontSize: 14, fontStyle: FontStyle.italic, color: fg)),
              ],
            )
          else if (message.type == 'image')
            _ImageBubble(
              imageUrl: message.imageUrl,
              caption: message.text,
              captionColor: fg,
              highlight: highlight,
            )
          else if (message.type == 'audio')
            _AudioBubble(
              playing: playing,
              onTap: onPlayAudio,
              color: fg,
            )
          else
            _HighlightedText(
              text: message.text ?? '',
              highlight: highlight,
              baseStyle: TextStyle(fontSize: 15, color: fg, height: 1.35),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _TimestampLabel(
              createdAt: message.createdAt,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  final String? imageUrl;
  final String? caption;
  final Color captionColor;
  final String? highlight;

  const _ImageBubble({
    required this.imageUrl,
    required this.caption,
    required this.captionColor,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: MediaCache.imageProvider(ApiService.resolveUrl(url)),
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => Container(
                width: 200,
                height: 200,
                alignment: Alignment.center,
                color: AppColors.canopy,
                child:
                    const Icon(Icons.broken_image_rounded, color: Colors.white),
              ),
            ),
          ),
        if ((caption ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
            child: _HighlightedText(
              text: caption!,
              highlight: highlight,
              baseStyle: TextStyle(fontSize: 14, color: captionColor),
            ),
          ),
      ],
    );
  }
}

class _AudioBubble extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  final Color color;

  const _AudioBubble(
      {required this.playing, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            playing
                ? Icons.pause_circle_filled_rounded
                : Icons.play_arrow_rounded,
            color: color,
            size: 30,
          ),
          const SizedBox(width: 6),
          Text('Voice message',
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final String? highlight;
  final TextStyle baseStyle;

  const _HighlightedText({
    required this.text,
    required this.highlight,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final query = highlight;
    if (query == null || query.isEmpty) {
      return Text(text, style: baseStyle);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var index = 0;
    while (index < text.length) {
      final match = lowerText.indexOf(lowerQuery, index);
      if (match < 0) {
        spans.add(TextSpan(text: text.substring(index)));
        break;
      }
      if (match > index) {
        spans.add(TextSpan(text: text.substring(index, match)));
      }
      spans.add(TextSpan(
        text: text.substring(match, match + query.length),
        style: const TextStyle(
          backgroundColor: Color(0x66FFC107),
          fontWeight: FontWeight.w700,
        ),
      ));
      index = match + query.length;
    }
    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}

// ---- Reply-preview widgets ------------------------------------------------

class _ReplyPreviewInsideBubble extends StatelessWidget {
  final RoomReplyPreview reply;
  final VoidCallback onTap;
  final bool dark;
  const _ReplyPreviewInsideBubble({
    required this.reply,
    required this.onTap,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = dark ? Colors.white70 : AppColors.inkSoft;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.18)
              : AppColors.canopy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
                color: dark ? Colors.white : AppColors.ochre, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              reply.senderName ?? 'Someone',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: dark ? Colors.white : AppColors.ochre),
            ),
            const SizedBox(height: 2),
            Text(
              reply.excerpt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: labelColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyComposerPreview extends StatelessWidget {
  final RoomMessage message;
  final VoidCallback onCancel;
  const _ReplyComposerPreview({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    String excerpt;
    if (message.type == 'audio') {
      excerpt = '🎤 Voice message';
    } else if (message.type == 'image') {
      excerpt = '📷 Photo';
    } else if (message.type == 'sticker') {
      excerpt = message.sticker ?? '';
    } else {
      excerpt = message.text ?? '';
    }
    return Container(
      color: AppColors.sandDim,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Container(width: 3, height: 40, color: AppColors.ochre),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Replying to ${message.senderName}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.ochre,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  excerpt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppColors.inkSoft,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

// ---- Reactions ------------------------------------------------------------

class _ReactionRow extends StatelessWidget {
  final Map<String, List<String>> reactions;
  final String currentUserId;
  final ValueChanged<String> onTap;

  const _ReactionRow({
    required this.reactions,
    required this.currentUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions.entries.map((entry) {
        final emoji = entry.key;
        final userIds = entry.value;
        final mine = userIds.contains(currentUserId);
        return GestureDetector(
          onTap: () => onTap(emoji),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:
                  mine ? AppColors.ochre.withValues(alpha: 0.18) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: mine ? AppColors.ochre : AppColors.sandDim,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text('${userIds.length}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _QuickReactionRow extends StatelessWidget {
  final RoomMessage message;
  final String currentUserId;
  final ValueChanged<String> onPick;

  const _QuickReactionRow({
    required this.message,
    required this.currentUserId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: _kQuickReactions.map((emoji) {
        final mine =
            (message.reactions[emoji] ?? const []).contains(currentUserId);
        return GestureDetector(
          onTap: () => onPick(emoji),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: mine
                  ? AppColors.ochre.withValues(alpha: 0.15)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
          ),
        );
      }).toList(),
    );
  }
}

// ---- Sender avatar --------------------------------------------------------

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;
  const _Avatar({required this.name, required this.url});

  @override
  Widget build(BuildContext context) {
    final resolved = url;
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.canopy,
      backgroundImage: resolved != null
          ? MediaCache.imageProvider(ApiService.resolveUrl(resolved), cacheWidth: 96)
          : null,
      child: resolved == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            )
          : null,
    );
  }
}

class _TimestampLabel extends StatelessWidget {
  final String createdAt;
  const _TimestampLabel({required this.createdAt});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(createdAt)?.toLocal();
    final label =
        date == null ? '' : TimeOfDay.fromDateTime(date).format(context);
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        color: ChatColors.muted,
      ),
    );
  }
}

// ---- Sticker picker -------------------------------------------------------

class _RoomStickerPicker extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _RoomStickerPicker({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.sandDim,
      height: 240,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: _kRoomStickers.length,
        itemBuilder: (context, index) {
          final sticker = _kRoomStickers[index];
          return InkWell(
            onTap: () => onPick(sticker),
            borderRadius: BorderRadius.circular(8),
            child: Center(
                child: Text(sticker, style: const TextStyle(fontSize: 28))),
          );
        },
      ),
    );
  }
}

// ---- Composer / input bar -------------------------------------------------

class _RoomInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool recording;
  final bool replying;
  final VoidCallback onSend;
  final VoidCallback onToggleStickers;
  final VoidCallback onToggleRecording;
  final VoidCallback onPickImage;
  final VoidCallback onTakePhoto;

  const _RoomInputBar({
    required this.controller,
    required this.sending,
    required this.recording,
    required this.replying,
    required this.onSend,
    required this.onToggleStickers,
    required this.onToggleRecording,
    required this.onPickImage,
    required this.onTakePhoto,
  });

  void _showAttachmentSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.sand,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.ochre),
              title: const Text('Photo from gallery'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onPickImage();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt_rounded, color: AppColors.ochre),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onTakePhoto();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: chatLabel(context, 'Stickers', 'Autocollants'),
              icon: const Icon(Icons.emoji_emotions_outlined),
              color: AppColors.inkSoft,
              onPressed: sending || recording ? null : onToggleStickers,
            ),
            IconButton(
              icon: const Icon(Icons.attach_file_rounded),
              tooltip: 'Attach a photo',
              color: AppColors.inkSoft,
              onPressed: sending || recording
                  ? null
                  : () => _showAttachmentSheet(context),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                enabled: !recording,
                decoration: InputDecoration(
                  hintText: recording
                      ? 'Recording…'
                      : replying
                          ? 'Reply to the message above'
                          : 'Message everyone',
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
                  return IconButton.filled(
                    tooltip: chatLabel(
                        context, 'Send message', 'Envoyer le message'),
                    style: IconButton.styleFrom(
                        backgroundColor: ChatColors.header,
                        foregroundColor: Colors.white),
                    icon: sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                    onPressed: sending ? null : onSend,
                  );
                }
                return IconButton(
                  tooltip: recording
                      ? chatLabel(
                          context, 'Stop and send', 'Arrêter et envoyer')
                      : chatLabel(context, 'Record voice message',
                          'Enregistrer un message vocal'),
                  icon: sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(recording
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
