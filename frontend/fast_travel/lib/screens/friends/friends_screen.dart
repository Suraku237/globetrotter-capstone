import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/voice_bytes.dart';

class FriendsScreen extends StatefulWidget {
  final SessionState session;

  const FriendsScreen({super.key, required this.session});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  FriendsOverview? _overview;
  List<ChatGroup> _groups = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        ApiService.instance.getFriendsOverview(),
        ApiService.instance.getGroups(),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = result[0] as FriendsOverview;
        _groups = result[1] as List<ChatGroup>;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendFriendRequest() async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add friend'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixText: '@',
            hintText: 'friend_username',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (username == null || username.trim().isEmpty || !mounted) return;

    try {
      await ApiService.instance.sendFriendRequest(username);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request sent.')),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    try {
      await ApiService.instance.acceptFriendRequest(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('You are now friends.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _declineRequest(String requestId) async {
    try {
      await ApiService.instance.declineFriendRequest(requestId);
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _createGroup() async {
    final friends = _overview?.friends ?? [];
    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add and connect with a friend first.')),
      );
      return;
    }

    final nameController = TextEditingController();
    final selectedIds = <String>{};
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create group'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Group name'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Add friends',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  ...friends.map(
                    (friend) => CheckboxListTile(
                      value: selectedIds.contains(friend.id),
                      contentPadding: EdgeInsets.zero,
                      title: Text(friend.fullName),
                      subtitle: Text('@${friend.username}'),
                      onChanged: (selected) => setDialogState(() {
                        if (selected ?? false) {
                          selectedIds.add(friend.id);
                        } else {
                          selectedIds.remove(friend.id);
                        }
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  selectedIds.isEmpty || nameController.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (created != true || !mounted) {
      nameController.dispose();
      return;
    }
    try {
      await ApiService.instance.createGroup(
        name: nameController.text,
        memberIds: selectedIds.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Group created.')));
      await _load();
      _tabs.animateTo(2);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      nameController.dispose();
    }
  }

  void _openFriend(SocialUser friend) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen.direct(
          session: widget.session,
          friend: friend,
        ),
      ),
    );
  }

  void _openGroup(ChatGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen.group(
          session: widget.session,
          group: group,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            tooltip: 'Create group',
            onPressed: _createGroup,
            icon: const Icon(Icons.group_add_rounded),
          ),
          IconButton(
            tooltip: 'Add friend',
            onPressed: _sendFriendRequest,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Friends'),
            Tab(
              text: _overview?.incomingRequests.isNotEmpty ?? false
                  ? 'Requests (${_overview!.incomingRequests.length})'
                  : 'Requests',
            ),
            const Tab(text: 'Groups'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.ochre))
          : _error != null
              ? _FailureState(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _friendsTab(),
                    _requestsTab(),
                    _groupsTab(),
                  ],
                ),
    );
  }

  Widget _friendsTab() {
    final friends = _overview?.friends ?? [];
    if (friends.isEmpty) {
      return _EmptyState(
        icon: Icons.people_outline_rounded,
        title: 'Connect with friends',
        message: 'Tap Add friend and enter a username to send a request.',
        actionLabel: 'Add friend',
        onAction: _sendFriendRequest,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: friends.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final friend = friends[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: _UserAvatar(user: friend, radius: 25),
            title: Text(friend.fullName),
            subtitle: Text('@${friend.username}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openFriend(friend),
          );
        },
      ),
    );
  }

  Widget _requestsTab() {
    final incoming = _overview?.incomingRequests ?? [];
    final outgoing = _overview?.outgoingRequests ?? [];
    if (incoming.isEmpty && outgoing.isEmpty) {
      return const _EmptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'No friend requests',
        message: 'Incoming requests will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (incoming.isNotEmpty) ...[
            Text('Incoming requests',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...incoming.map(
              (request) => Card(
                child: ListTile(
                  leading: _UserAvatar(user: request.user, radius: 23),
                  title: Text(request.user.fullName),
                  subtitle: Text('@${request.user.username} wants to connect'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Ignore',
                        onPressed: () => _declineRequest(request.requestId),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      IconButton(
                        tooltip: 'Accept',
                        onPressed: () => _acceptRequest(request.requestId),
                        icon: const Icon(Icons.check_rounded,
                            color: AppColors.ochre),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (outgoing.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Sent requests',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...outgoing.map(
              (request) => ListTile(
                leading: _UserAvatar(user: request.user, radius: 23),
                title: Text(request.user.fullName),
                subtitle: Text('@${request.user.username} • Pending'),
                trailing: const Icon(Icons.schedule_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _groupsTab() {
    if (_groups.isEmpty) {
      return _EmptyState(
        icon: Icons.forum_outlined,
        title: 'Create a group',
        message: 'Start a group conversation with your friends.',
        actionLabel: 'Create group',
        onAction: _createGroup,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _groups.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final group = _groups[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: AppColors.ochre.withValues(alpha: 0.2),
              child: const Icon(Icons.groups_rounded, color: AppColors.ochre),
            ),
            title: Text(group.name),
            subtitle: Text('${group.members.length} members'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openGroup(group),
          );
        },
      ),
    );
  }
}

class ConversationScreen extends StatefulWidget {
  final SessionState session;
  final SocialUser? friend;
  final ChatGroup? group;

  const ConversationScreen.direct({
    super.key,
    required this.session,
    required SocialUser this.friend,
  }) : group = null;

  const ConversationScreen.group({
    super.key,
    required this.session,
    required ChatGroup this.group,
  }) : friend = null;

  bool get isGroup => group != null;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  List<SocialMessage> _messages = [];
  Timer? _poller;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  // Sticker + emoji picker state — only one of these is open at a time
  // so the composer stays usable and the keyboard has room to appear.
  _PickerPanel _openPicker = _PickerPanel.none;
  List<ChatSticker>? _stickers;
  bool _loadingStickers = false;

  // Voice recorder / uploader state.
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _uploadingVoice = false;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTicker;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    _poller = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _load(),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    _recordingTicker?.cancel();
    // Best-effort — if we're mid-recording when the screen closes,
    // discard the take rather than leaving the mic engaged.
    _recorder.stop().then((path) async {
      await _recorder.dispose();
    }).catchError((_) async {
      await _recorder.dispose();
    });
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final messages = widget.isGroup
          ? await ApiService.instance.getGroupMessages(widget.group!.id)
          : await ApiService.instance.getDirectMessages(widget.friend!.id);
      if (!mounted) return;
      final added = messages.length > _messages.length;
      setState(() {
        _messages = messages;
        _error = null;
      });
      if (initial || added) _scrollToBottom();
    } on ApiException catch (error) {
      if (mounted && initial) setState(() => _error = error.message);
    } finally {
      if (mounted && initial) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    _composer.clear();
    setState(() => _sending = true);
    try {
      final message = widget.isGroup
          ? await ApiService.instance
              .sendGroupMessage(widget.group!.id, text: text)
          : await ApiService.instance
              .sendDirectMessage(widget.friend!.id, text: text);
      if (!mounted) return;
      setState(() => _messages = [..._messages, message]);
      _scrollToBottom();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendSticker(ChatSticker sticker) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _openPicker = _PickerPanel.none;
    });
    try {
      final message = widget.isGroup
          ? await ApiService.instance
              .sendGroupMessage(widget.group!.id, stickerId: sticker.id)
          : await ApiService.instance
              .sendDirectMessage(widget.friend!.id, stickerId: sticker.id);
      if (!mounted) return;
      setState(() => _messages = [..._messages, message]);
      _scrollToBottom();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _togglePicker(_PickerPanel panel) async {
    // Any open picker hides the on-screen keyboard so the picker gets
    // full height — otherwise the picker collides with the keyboard on
    // mobile and the user sees neither properly.
    FocusScope.of(context).unfocus();
    setState(() {
      _openPicker = _openPicker == panel ? _PickerPanel.none : panel;
    });
    if (_openPicker == _PickerPanel.stickers &&
        _stickers == null &&
        !_loadingStickers) {
      setState(() => _loadingStickers = true);
      try {
        final stickers = await ApiService.instance.getStickers();
        if (mounted) setState(() => _stickers = stickers);
      } on ApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      } finally {
        if (mounted) setState(() => _loadingStickers = false);
      }
    }
  }

  void _insertEmoji(String emoji) {
    // Insert at the current selection so the caret lands after the
    // emoji rather than jumping to the end of the field.
    final value = _composer.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final newText =
        value.text.replaceRange(selection.start, selection.end, emoji);
    _composer.value = value.copyWith(
      text: newText,
      selection:
          TextSelection.collapsed(offset: selection.start + emoji.length),
    );
  }

  Future<void> _startRecording() async {
    if (_recording || _uploadingVoice) return;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
        return;
      }
      setState(() {
        _openPicker = _PickerPanel.none;
        _recordingElapsed = Duration.zero;
      });

      // AAC in an MP4 container plays back on every platform Flutter
      // targets without an extra codec plugin. Web falls back to
      // whatever the browser can record via the same package — the
      // container is transparent to us here.
      const config = RecordConfig(encoder: AudioEncoder.aacLc);
      if (kIsWeb) {
        await _recorder.start(config, path: '');
      } else {
        // A path is required on native platforms — a stable name under
        // the app's temp area is picked automatically by the plugin
        // when using record 5.x with an explicit temp path.
        await _recorder.start(config,
            path: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      }

      setState(() => _recording = true);
      _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordingElapsed += const Duration(seconds: 1));
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start recording: $error')),
      );
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingElapsed = Duration.zero;
    });
  }

  Future<void> _stopAndSendRecording() async {
    if (!_recording) return;
    _recordingTicker?.cancel();
    _recordingTicker = null;
    setState(() {
      _recording = false;
      _uploadingVoice = true;
    });

    try {
      final path = await _recorder.stop();
      if (path == null || path.isEmpty) {
        throw Exception('Recording was empty');
      }

      final Uint8List bytes = await readVoiceBytes(path);
      String filename;
      if (kIsWeb) {
        filename = 'voice.webm';
      } else {
        filename = path.split(RegExp(r'[\\/]')).last;
        if (!filename.contains('.')) filename = '$filename.m4a';
      }

      final durationMs = _recordingElapsed.inMilliseconds > 0
          ? _recordingElapsed.inMilliseconds
          : 1000;

      final uploaded = await ApiService.instance.uploadVoiceMessage(
        bytes: bytes,
        filename: filename,
        durationMs: durationMs,
      );

      final message = widget.isGroup
          ? await ApiService.instance.sendGroupMessage(
              widget.group!.id,
              voiceUrl: uploaded.url,
              voiceDurationMs: uploaded.durationMs,
            )
          : await ApiService.instance.sendDirectMessage(
              widget.friend!.id,
              voiceUrl: uploaded.url,
              voiceDurationMs: uploaded.durationMs,
            );
      if (!mounted) return;
      setState(() => _messages = [..._messages, message]);
      _scrollToBottom();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send voice message: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingVoice = false;
          _recordingElapsed = Duration.zero;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isGroup ? widget.group!.name : widget.friend!.fullName;
    final subtitle = widget.isGroup
        ? '${widget.group!.members.length} members'
        : '@${widget.friend!.username}';
    return Scaffold(
      appBar: AppBar(
          title: Text(title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child:
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ),
          )),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.ochre))
                : _error != null
                    ? _FailureState(
                        message: _error!, onRetry: () => _load(initial: true))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (_, index) {
                          final message = _messages[index];
                          return _MessageBubble(
                            message: message,
                            mine: message.senderId ==
                                widget.session.currentUser?.id,
                            showSender: widget.isGroup,
                            stickers: _stickers,
                          );
                        },
                      ),
          ),
          if (_openPicker == _PickerPanel.emoji) _emojiPanel(),
          if (_openPicker == _PickerPanel.stickers) _stickerPanel(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: _recording ? _recordingBar() : _composerBar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composerBar() {
    final canSendText = !_sending && !_uploadingVoice;
    return Row(
      children: [
        IconButton(
          tooltip: 'Emoji',
          onPressed:
              canSendText ? () => _togglePicker(_PickerPanel.emoji) : null,
          icon: Icon(
            Icons.emoji_emotions_outlined,
            color: _openPicker == _PickerPanel.emoji ? AppColors.ochre : null,
          ),
        ),
        IconButton(
          tooltip: 'Sticker',
          onPressed:
              canSendText ? () => _togglePicker(_PickerPanel.stickers) : null,
          icon: Icon(
            Icons.sticky_note_2_outlined,
            color:
                _openPicker == _PickerPanel.stickers ? AppColors.ochre : null,
          ),
        ),
        Expanded(
          child: TextField(
            controller: _composer,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            onTap: () => setState(() => _openPicker = _PickerPanel.none),
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              hintText: 'Write a message',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Toggle between the send button (when there's text to send) and
        // the mic button (when the composer is empty) — matches the
        // pattern people already know from WhatsApp/Telegram, so the
        // control moves out of the way instead of adding a fourth icon.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _composer,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty;
            if (hasText) {
              return IconButton.filled(
                tooltip: 'Send message',
                onPressed: canSendText ? _send : null,
                icon: const Icon(Icons.send_rounded),
              );
            }
            return IconButton.filled(
              tooltip: 'Record voice message',
              onPressed: _uploadingVoice ? null : _startRecording,
              icon: _uploadingVoice
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.mic_rounded),
            );
          },
        ),
      ],
    );
  }

  Widget _recordingBar() {
    // Compact but expressive recording bar — matches the messaging apps
    // people already know: cancel on the left, elapsed time in the
    // middle (with a red pulse dot for "I really am recording"), and
    // stop-and-send on the right.
    final minutes = _recordingElapsed.inMinutes.remainder(60);
    final seconds = _recordingElapsed.inSeconds.remainder(60);
    final elapsed =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return Row(
      children: [
        IconButton(
          tooltip: 'Cancel recording',
          onPressed: _cancelRecording,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
        Expanded(
          child: Row(
            children: [
              const _PulsingDot(color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('Recording  $elapsed',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        IconButton.filled(
          tooltip: 'Stop and send',
          onPressed: _stopAndSendRecording,
          icon: const Icon(Icons.send_rounded),
        ),
      ],
    );
  }

  Widget _emojiPanel() {
    // Small curated list — plenty to add colour to a message without
    // pulling a heavyweight emoji-picker dependency. The pickers on
    // real phones can still insert any emoji through the keyboard.
    const emojis = <String>[
      '\u{1F600}',
      '\u{1F602}',
      '\u{1F60D}',
      '\u{1F609}',
      '\u{1F914}',
      '\u{1F60E}',
      '\u{1F607}',
      '\u{1F929}',
      '\u{1F631}',
      '\u{1F622}',
      '\u{1F44D}',
      '\u{1F44F}',
      '\u{1F64C}',
      '\u{1F64F}',
      '\u{1F91D}',
      '\u{2764}\u{FE0F}',
      '\u{1F525}',
      '\u{2728}',
      '\u{1F389}',
      '\u{1F4AF}',
      '\u{2600}\u{FE0F}',
      '\u{1F308}',
      '\u{1F30D}',
      '\u{2708}\u{FE0F}',
      '\u{1F3D6}\u{FE0F}',
      '\u{1F4F8}',
      '\u{1F37D}\u{FE0F}',
      '\u{2615}',
      '\u{1F37A}',
      '\u{1F382}',
      '\u{1F31F}',
      '\u{2705}',
    ];
    return Container(
      color: AppColors.sand.withValues(alpha: 0.35),
      constraints: const BoxConstraints(maxHeight: 220),
      child: GridView.count(
        crossAxisCount: 8,
        padding: const EdgeInsets.all(8),
        children: emojis
            .map(
              (e) => InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _insertEmoji(e),
                child: Center(
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _stickerPanel() {
    return Container(
      color: AppColors.sand.withValues(alpha: 0.35),
      constraints: const BoxConstraints(maxHeight: 240),
      child: _loadingStickers
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.ochre),
            )
          : (_stickers == null || _stickers!.isEmpty)
              ? const Center(
                  child: Text('No stickers available.'),
                )
              : GridView.count(
                  crossAxisCount: 4,
                  padding: const EdgeInsets.all(8),
                  children: _stickers!
                      .map(
                        (sticker) => InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _sending ? null : () => _sendSticker(sticker),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(sticker.emoji,
                                  style: const TextStyle(fontSize: 40)),
                              const SizedBox(height: 2),
                              Text(sticker.label,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
    );
  }
}

enum _PickerPanel { none, emoji, stickers }

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final SocialMessage message;
  final bool mine;
  final bool showSender;
  final List<ChatSticker>? stickers;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showSender,
    required this.stickers,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  AudioPlayer? _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _ensurePlayer() async {
    if (_player != null) return;
    final player = AudioPlayer();
    _stateSub = player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _positionSub = player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _durationSub = player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
    });
    _player = player;
  }

  Future<void> _toggleVoice(String voiceUrl) async {
    await _ensurePlayer();
    final player = _player!;
    if (_playing) {
      await player.pause();
      return;
    }
    final absoluteUrl = ApiService.resolveUrl(voiceUrl);
    await player.play(UrlSource(absoluteUrl));
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    // Sticker messages are rendered without a bubble background — the
    // sticker itself is the visual — matching how big platforms handle
    // one-shot reactions.
    if (message.type == 'sticker') return _buildSticker(context, message);

    final color = widget.mine ? AppColors.ochre : AppColors.sand;
    final textColor = widget.mine ? Colors.white : AppColors.ink;

    Widget content;
    if (message.type == 'voice' && (message.voiceUrl ?? '').isNotEmpty) {
      content = _voiceContent(textColor, message);
    } else {
      content = Text(message.text, style: TextStyle(color: textColor));
    }

    return Align(
      alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showSender && !widget.mine)
              Text(message.senderName,
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildSticker(BuildContext context, SocialMessage message) {
    // Server-side catalog is authoritative — fall back to a neutral
    // question mark if the client hasn't loaded stickers yet or a new
    // sticker id shipped after this build.
    final sticker = widget.stickers?.firstWhere(
      (item) => item.id == message.stickerId,
      orElse: () => const ChatSticker(id: '?', emoji: '\u2753', label: ''),
    );
    return Align(
      alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment:
              widget.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (widget.showSender && !widget.mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Text(
              sticker?.emoji ?? '\u2753',
              style: const TextStyle(fontSize: 64),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceContent(Color textColor, SocialMessage message) {
    final total = _duration.inMilliseconds > 0
        ? _duration
        : Duration(milliseconds: message.voiceDurationMs ?? 0);
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final label = _formatDuration(total.inMilliseconds > 0
        ? (_playing ? _position : total)
        : Duration(milliseconds: message.voiceDurationMs ?? 0));
    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _toggleVoice(message.voiceUrl!),
            icon: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: textColor,
              size: 32,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: textColor.withValues(alpha: 0.25),
              color: textColor,
              minHeight: 3,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: textColor, fontSize: 12)),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _UserAvatar extends StatelessWidget {
  final SocialUser user;
  final double radius;

  const _UserAvatar({required this.user, required this.radius});

  @override
  Widget build(BuildContext context) {
    final initials = user.fullName.trim().isEmpty
        ? '?'
        : user.fullName.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.ochre.withValues(alpha: 0.2),
      backgroundImage: user.avatarUrl == null
          ? null
          : NetworkImage(ApiService.resolveUrl(user.avatarUrl!)),
      child: user.avatarUrl == null
          ? Text(initials,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.ochre))
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.ochre),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FailureState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _FailureState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 52, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
