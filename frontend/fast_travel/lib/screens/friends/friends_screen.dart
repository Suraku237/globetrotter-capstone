import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:record/record.dart';

import '../../Services/api_service.dart';
import '../../Services/media_cache.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/voice_bytes.dart';
import '../../Services/call_coordinator.dart';
import '../../models/call_models.dart';
import '../chat/chat_ui.dart';

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
  late final ChatRefreshController _updates;
  final _pendingRequests = <String>{};
  final _resolvedRequests = <String>{};
  final _acceptedFriends = <String, SocialUser>{};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _updates = ChatRefreshController(
      changes: ApiService.instance.changes,
      topics: const {'friends'},
      isLive: () => ApiService.instance.isLive,
      isVisible: () =>
          mounted &&
          TickerMode.of(context) &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      load: _load,
      invalidate: ApiService.instance.refreshTopics,
    )..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updates.visibilityChanged();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _updates.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await Future.wait([
        ApiService.instance.getFriendsOverview(),
        ApiService.instance.getGroups(),
      ]);
      if (!mounted) return;
      setState(() {
        final overview = result[0] as FriendsOverview;
        final incomingIds = overview.incomingRequests
            .map((request) => request.requestId)
            .toSet();
        _resolvedRequests.removeWhere((id) => !incomingIds.contains(id));
        final friendIds = overview.friends.map((friend) => friend.id).toSet();
        _acceptedFriends.removeWhere((id, _) => friendIds.contains(id));
        // A stale cache read must not undo a confirmed approval.
        _overview = FriendsOverview(
          friends: {
            for (final friend in overview.friends) friend.id: friend,
            ..._acceptedFriends,
          }.values.toList(),
          incomingRequests: overview.incomingRequests
              .where((request) =>
                  !_resolvedRequests.contains(request.requestId) &&
                  !_acceptedFriends.containsKey(request.user.id))
              .toList(),
          outgoingRequests: overview.outgoingRequests,
        );
        _groups = result[1] as List<ChatGroup>;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
            ? error.message
            : chatLabel(context, 'Could not refresh your friends.',
                "Impossible d'actualiser vos amis."));
      }
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
      await _updates.refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    if (!_pendingRequests.add(requestId)) return;
    setState(() {});
    try {
      await ApiService.instance.acceptFriendRequest(requestId);
      if (!mounted) return;
      setState(() {
        final overview = _overview;
        if (overview == null) return;
        final accepted = overview.incomingRequests
            .where((request) => request.requestId == requestId)
            .map((request) => request.user);
        _resolvedRequests.add(requestId);
        for (final user in accepted) {
          _acceptedFriends[user.id] = user;
        }
        _overview = FriendsOverview(
          friends: {
            for (final user in [...overview.friends, ...accepted])
              user.id: user,
          }.values.toList(),
          incomingRequests: overview.incomingRequests
              .where((request) => request.requestId != requestId)
              .toList(),
          outgoingRequests: overview.outgoingRequests,
        );
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('You are now friends.')));
      await _updates.refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _pendingRequests.remove(requestId));
    }
  }

  Future<void> _declineRequest(String requestId) async {
    if (!_pendingRequests.add(requestId)) return;
    setState(() {});
    try {
      await ApiService.instance.declineFriendRequest(requestId);
      if (!mounted) return;
      setState(() {
        final overview = _overview;
        if (overview == null) return;
        _resolvedRequests.add(requestId);
        _overview = FriendsOverview(
          friends: overview.friends,
          incomingRequests: overview.incomingRequests
              .where((request) => request.requestId != requestId)
              .toList(),
          outgoingRequests: overview.outgoingRequests,
        );
      });
      await _updates.refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _pendingRequests.remove(requestId));
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
      await _updates.refresh();
      if (mounted) _tabs.animateTo(2);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      nameController.dispose();
    }
  }

  Future<void> _openFriend(SocialUser friend) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen.direct(
          session: widget.session,
          friend: friend,
        ),
      ),
    );
    if (mounted) unawaited(_updates.refresh());
  }

  Future<void> _openGroup(ChatGroup group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen.group(
          session: widget.session,
          group: group,
        ),
      ),
    );
    if (mounted) unawaited(_updates.refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: ChatColors.header,
        foregroundColor: Colors.white,
        title:
            Text(chatLabel(context, 'Chats & friends', 'Discussions et amis')),
        actions: [
          IconButton(
            tooltip: 'Enable call notifications',
            onPressed: CallCoordinator.instance.enableNotifications,
            icon: const Icon(Icons.notifications_active_outlined),
          ),
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
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
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
          : _error != null && _overview == null
              ? _FailureState(message: _error!, onRetry: _updates.refreshFromNetwork)
              : Column(
                  children: [
                    if (_error != null)
                      ChatNotice(message: _error!, onRetry: _updates.refreshFromNetwork),
                    Expanded(
                        child: TabBarView(
                      controller: _tabs,
                      children: [
                        _friendsTab(),
                        _requestsTab(),
                        _groupsTab(),
                      ],
                    )),
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
      onRefresh: _updates.refreshFromNetwork,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: friends.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final friend = friends[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: _UserAvatar(user: friend, radius: 25),
            title: Text(friend.fullName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('@${friend.username}',
                style: const TextStyle(color: ChatColors.muted)),
            trailing: const Icon(Icons.chat_bubble_outline_rounded,
                size: 20, color: ChatColors.header),
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
      onRefresh: _updates.refreshFromNetwork,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                  trailing: _pendingRequests.contains(request.requestId)
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Ignore',
                              onPressed: () =>
                                  _declineRequest(request.requestId),
                              icon: const Icon(Icons.close_rounded),
                            ),
                            IconButton(
                              tooltip: 'Accept',
                              onPressed: () =>
                                  _acceptRequest(request.requestId),
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
      onRefresh: _updates.refreshFromNetwork,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _groups.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final group = _groups[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: ChatColors.header.withValues(alpha: 0.15),
              child: const Icon(Icons.groups_rounded, color: ChatColors.header),
            ),
            title: Text(group.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${group.members.length} members',
                style: const TextStyle(color: ChatColors.muted)),
            trailing: const Icon(Icons.chat_bubble_outline_rounded,
                size: 20, color: ChatColors.header),
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
  String? _oldestCursor;
  bool _loadingOlder = false;
  bool _canLoadOlder = false;
  bool _historyLoaded = false;
  late final ChatRefreshController _updates;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _sendError;
  Future<void> Function()? _retrySend;
  bool _hasNewMessages = false;

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
  Future<void>? _startingRecording;

  @override
  void initState() {
    super.initState();
    _updates = ChatRefreshController(
      changes: ApiService.instance.changes,
      topics: const {'friends'},
      isLive: () => ApiService.instance.isLive,
      isVisible: () =>
          mounted &&
          TickerMode.of(context) &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      load: _load,
      invalidate: ApiService.instance.refreshTopics,
    )..start();
    CallCoordinator.instance.beforeConnect = _releaseMicrophoneForCall;
    _scrollController.addListener(() {
      if (_hasNewMessages && _nearBottom) {
        setState(() => _hasNewMessages = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updates.visibilityChanged();
  }

  @override
  void dispose() {
    if (CallCoordinator.instance.beforeConnect == _releaseMicrophoneForCall) {
      CallCoordinator.instance.beforeConnect = null;
    }
    _updates.dispose();
    _recordingTicker?.cancel();
    unawaited(_disposeRecorder());
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _disposeRecorder() async {
    await _startingRecording;
    try {
      await _recorder.stop();
    } on PlatformException catch (error) {
      debugPrint('Unable to stop voice recorder during cleanup: ${error.code}');
    } finally {
      await _recorder.dispose();
    }
  }

  bool get _nearBottom =>
      !_scrollController.hasClients ||
      _scrollController.position.extentAfter < 96;

  List<SocialMessage> _merge(Iterable<SocialMessage> incoming) =>
      mergeChatMessages(_messages, incoming,
          id: (message) => message.id,
          createdAt: (message) => message.createdAt);

  Future<void> _load() async {
    if (_loadingOlder) return;
    final initial = _loading;
    try {
      final messages = widget.isGroup
          ? await ApiService.instance.getGroupMessages(widget.group!.id)
          : await ApiService.instance.getDirectMessages(widget.friend!.id);
      if (!mounted) return;
      final ids = _messages.map((message) => message.id).toSet();
      final added = messages.any((message) => !ids.contains(message.id));
      final follow = initial || _nearBottom;
      setState(() {
        _messages = _merge(messages);
        if (messages.isNotEmpty) _oldestCursor ??= messages.first.id;
        if (!_historyLoaded) _canLoadOlder = messages.length >= 50;
        _error = null;
        if (added && !follow) _hasNewMessages = true;
      });
      if (follow && (initial || added)) _scrollToBottom();
      if (_stickers == null &&
          !_loadingStickers &&
          messages.any((message) => message.type == 'sticker')) {
        unawaited(_loadStickers());
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_canLoadOlder || _oldestCursor == null) return;
    setState(() => _loadingOlder = true);
    try {
      final older = widget.isGroup
          ? await ApiService.instance.getGroupMessages(widget.group!.id, before: _oldestCursor)
          : await ApiService.instance.getDirectMessages(widget.friend!.id, before: _oldestCursor);
      if (!mounted) return;
      final position = _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
      final extent = _scrollController.hasClients ? _scrollController.position.maxScrollExtent : 0.0;
      setState(() {
        _messages = mergeChatMessages(older, _messages,
            id: (message) => message.id, createdAt: (message) => message.createdAt);
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
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.message),
          action: SnackBarAction(label: chatLabel(context, 'Retry', 'Reessayer'), onPressed: _loadOlder),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingOlder = false);
        unawaited(_updates.refresh());
      }
    }
  }

  Future<void> _send() async {
    final draft = _composer.text;
    if (draft.trim().isEmpty || _sending || _uploadingVoice || _recording)
      return;
    await _sendMessage(
      () => widget.isGroup
          ? ApiService.instance
              .sendGroupMessage(widget.group!.id, text: draft.trim())
          : ApiService.instance
              .sendDirectMessage(widget.friend!.id, text: draft.trim()),
      draft: draft,
      retry: _send,
    );
  }

  Future<void> _sendMessage(
    Future<SocialMessage> Function() send, {
    String? draft,
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
        if (draft != null && _composer.text == draft) _composer.clear();
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
        _retrySend = retry ?? () => _sendMessage(send, draft: draft);
      });
      unawaited(_updates.refreshFromNetwork());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retryFailedSend() async {
    final retry = _retrySend;
    if (retry == null || _sending || _uploadingVoice || _recording) return;
    if (await confirmChatRetry(context) && mounted) await retry();
  }

  Future<void> _sendSticker(ChatSticker sticker) async {
    if (_sending || _uploadingVoice || _recording) return;
    setState(() => _openPicker = _PickerPanel.none);
    await _sendMessage(() => widget.isGroup
        ? ApiService.instance
            .sendGroupMessage(widget.group!.id, stickerId: sticker.id)
        : ApiService.instance
            .sendDirectMessage(widget.friend!.id, stickerId: sticker.id));
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
      await _loadStickers();
    }
  }

  Future<void> _loadStickers() async {
    if (_loadingStickers) return;
    setState(() => _loadingStickers = true);
    try {
      final stickers = await ApiService.instance.getStickers();
      if (mounted) setState(() => _stickers = stickers);
    } catch (_) {
      // Opening the sticker picker offers another attempt.
    } finally {
      if (mounted) setState(() => _loadingStickers = false);
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

  Future<void> _startRecording() {
    return _startingRecording ??=
        _startRecordingImpl().whenComplete(() => _startingRecording = null);
  }

  Future<void> _startRecordingImpl() async {
    if (_recording || _uploadingVoice || _sending) return;
    if (CallCoordinator.instance.isInCall) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Finish the call before recording a message.')),
      );
      return;
    }
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!mounted || CallCoordinator.instance.isInCall) return;
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

      if (!mounted || CallCoordinator.instance.isInCall) {
        await _recorder.stop();
        return;
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

  Future<void> _releaseMicrophoneForCall() async {
    await _startingRecording;
    if (!_recording) return;
    _recordingTicker?.cancel();
    _recordingTicker = null;
    try {
      await _recorder.stop();
    } on PlatformException catch (error) {
      throw ApiException(
          'Cannot release the microphone: ${error.message ?? error.code}');
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingElapsed = Duration.zero;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Voice recording stopped to answer the call.')),
    );
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

      String? uploadedUrl;
      int? uploadedDuration;
      await _sendMessage(() async {
        if (uploadedUrl == null) {
          final uploaded = await ApiService.instance.uploadVoiceMessage(
            bytes: bytes,
            filename: filename,
            durationMs: durationMs,
          );
          uploadedUrl = uploaded.url;
          uploadedDuration = uploaded.durationMs;
        }
        return widget.isGroup
            ? ApiService.instance.sendGroupMessage(
                widget.group!.id,
                voiceUrl: uploadedUrl,
                voiceDurationMs: uploadedDuration,
              )
            : ApiService.instance.sendDirectMessage(
                widget.friend!.id,
                voiceUrl: uploadedUrl,
                voiceDurationMs: uploadedDuration,
              );
      });
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

  // Resolves the avatar for whoever sent a given message. Direct chats
  // only ever have two participants so it's a straight either/or; group
  // chats look the sender up in the member list. Falls back to null
  // (initials avatar) for a member who has since left the group.
  SocialUser? _senderProfile(SocialMessage message, {required bool mine}) {
    if (mine) {
      final me = widget.session.currentUser;
      if (me == null) return null;
      return SocialUser(
        id: me.id,
        fullName: me.fullName,
        username: me.username,
        avatarUrl: me.avatarUrl,
      );
    }
    if (!widget.isGroup) return widget.friend;
    for (final member in widget.group!.members) {
      if (member.id == message.senderId) return member;
    }
    return null;
  }

  Future<void> _startCall(CallKind kind) async {
    if (_recording || _uploadingVoice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Finish your voice message before calling.')),
      );
      return;
    }
    await CallCoordinator.instance.startCall(
      kind: kind,
      targetType: widget.isGroup ? 'group' : 'direct',
      targetId: widget.isGroup ? widget.group!.id : widget.friend!.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isGroup ? widget.group!.name : widget.friend!.fullName;
    final subtitle = widget.isGroup
        ? '${widget.group!.members.length} members'
        : '@${widget.friend!.username}';
    final myId = widget.session.currentUser?.id;

    return Scaffold(
      backgroundColor: ChatColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: ChatColors.header,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            _ConversationAvatar(
              avatarUrl: widget.isGroup ? null : widget.friend!.avatarUrl,
              name: title,
              radius: 18,
              isGroup: widget.isGroup,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: chatLabel(context, 'Refresh messages', 'Actualiser les messages'),
            onPressed: _updates.refreshFromNetwork,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Voice call',
            onPressed: () => _startCall(CallKind.voice),
            icon: const Icon(Icons.call_rounded),
          ),
          IconButton(
            tooltip: 'Video call',
            onPressed: () => _startCall(CallKind.video),
            icon: const Icon(Icons.videocam_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_error != null && _messages.isNotEmpty)
            ChatNotice(message: _error!, onRetry: _updates.refreshFromNetwork),
          Expanded(
            child: ColoredBox(
              color: ChatColors.background,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.ochre))
                  : _error != null && _messages.isEmpty
                      ? _FailureState(
                          message: _error!, onRetry: _updates.refreshFromNetwork)
                      : _messages.isEmpty
                          ? _emptyConversation(title)
                          : _messageList(myId),
            ),
          ),
          if (_hasNewMessages)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() => _hasNewMessages = false);
                    _scrollToBottom();
                  },
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  label:
                      Text(chatLabel(context, 'New messages', 'Nouveaux messages')),
                ),
              ),
            ),
          if (_sendError != null)
            ChatNotice(
              message: _sendError!,
              onRetry: _sending || _uploadingVoice ? null : _retryFailedSend,
              onDismiss: () => setState(() {
                _sendError = null;
                _retrySend = null;
              }),
            ),
          if (_openPicker == _PickerPanel.emoji) _emojiPanel(),
          if (_openPicker == _PickerPanel.stickers) _stickerPanel(),
          Container(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: _recording ? _recordingBar() : _composerBar(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageList(String? myId) {
    return ListView.builder(
      controller: _scrollController,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index =
            _messages.indexWhere((message) => message.id == key.value);
        return index < 0 ? null : index + 1;
      },
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      itemCount: _messages.length + 1,
      itemBuilder: (_, itemIndex) {
        if (itemIndex == 0) {
          return Center(child: _loadingOlder
              ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
              : _canLoadOlder
                  ? TextButton.icon(onPressed: _loadOlder, icon: const Icon(Icons.history),
                      label: Text(chatLabel(context, 'Load older messages', 'Messages precedents')))
                  : const SizedBox.shrink());
        }
        final index = itemIndex - 1;
        final message = _messages[index];
        final mine = message.senderId == myId;
        final previous = index == 0 ? null : _messages[index - 1];
        final next =
            index == _messages.length - 1 ? null : _messages[index + 1];

        // Only the last message of a run carries the avatar, and only the
        // first carries the sender name — the classic messaging-app
        // grouping that stops a burst of replies looking like a column
        // of disconnected cards.
        final isRunStart = previous == null ||
            previous.senderId != message.senderId ||
            !sameChatRun(previous.createdAt, message.createdAt);
        final isRunEnd = next == null ||
            next.senderId != message.senderId ||
            !sameChatRun(message.createdAt, next.createdAt);

        return Column(
          key: ValueKey(message.id),
          children: [
            if (startsChatDay(previous?.createdAt, message.createdAt))
              ChatDateSeparator(timestamp: message.createdAt),
            _MessageBubble(
              message: message,
              mine: mine,
              showSender: widget.isGroup && isRunStart && !mine,
              showAvatar: isRunEnd,
              isRunEnd: isRunEnd,
              sender: _senderProfile(message, mine: mine),
              stickers: _stickers,
            ),
          ],
        );
      },
    );
  }

  Widget _emptyConversation(String title) {
    final first = title.split(' ').first;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ChatColors.header.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.waving_hand_rounded,
                  color: ChatColors.header, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              widget.isGroup ? 'Say hello to the group' : 'Say hello to $first',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ChatColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Messages, voice notes and stickers all live here. '
              'Tap the call buttons above to ring them instead.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ChatColors.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
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
            decoration: InputDecoration(
              hintText: 'Write a message',
              filled: true,
              fillColor: ChatColors.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
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
                style: IconButton.styleFrom(
                    backgroundColor: ChatColors.header,
                    foregroundColor: Colors.white),
                onPressed: canSendText ? _send : null,
                icon: _sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
              );
            }
            return IconButton.filled(
              tooltip: 'Record voice message',
              style: IconButton.styleFrom(
                  backgroundColor: ChatColors.header,
                  foregroundColor: Colors.white),
              onPressed: canSendText ? _startRecording : null,
              icon: _uploadingVoice || _sending
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
  // Only the final message in a run from one person carries an avatar,
  // so a burst of replies reads as one block instead of a stack of
  // repeated faces.
  final bool showAvatar;
  final bool isRunEnd;
  final SocialUser? sender;
  final List<ChatSticker>? stickers;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showSender,
    required this.showAvatar,
    required this.isRunEnd,
    required this.sender,
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

    final color = widget.mine ? ChatColors.outgoing : Colors.white;
    const textColor = ChatColors.ink;

    Widget content;
    if (message.type == 'voice' && (message.voiceUrl ?? '').isNotEmpty) {
      content = _voiceContent(textColor, message);
    } else {
      content = Text(
        message.text,
        style: TextStyle(color: textColor, height: 1.32),
      );
    }

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
      decoration: BoxDecoration(
        color: color,
        // The corner nearest the avatar is squared off on the last
        // message of a run, giving the group a "tail" pointing at whoever
        // sent it.
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(
            !widget.mine && widget.isRunEnd ? 4 : 16,
          ),
          bottomRight: Radius.circular(
            widget.mine && widget.isRunEnd ? 4 : 16,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showSender)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                message.senderName,
                style: TextStyle(
                  color: widget.mine
                      ? textColor.withValues(alpha: 0.85)
                      : AppColors.ochre,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          content,
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _formatClock(message.createdAt),
              style: TextStyle(
                color: textColor.withValues(alpha: 0.62),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    return _AvatarRow(
      mine: widget.mine,
      showAvatar: widget.showAvatar,
      isRunEnd: widget.isRunEnd,
      sender: widget.sender,
      fallbackName: message.senderName,
      child: bubble,
    );
  }

  // "14:32" in the viewer's own locale/timezone. Falls back to an empty
  // string for the handful of legacy rows whose timestamp won't parse,
  // rather than printing a raw ISO string in the corner of the bubble.
  String _formatClock(String iso) {
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return '';
    return TimeOfDay.fromDateTime(parsed).format(context);
  }

  Widget _buildSticker(BuildContext context, SocialMessage message) {
    // Server-side catalog is authoritative — fall back to a neutral
    // question mark if the client hasn't loaded stickers yet or a new
    // sticker id shipped after this build.
    final sticker = widget.stickers?.firstWhere(
      (item) => item.id == message.stickerId,
      orElse: () => const ChatSticker(id: '?', emoji: '\u2753', label: ''),
    );
    return _AvatarRow(
      mine: widget.mine,
      showAvatar: widget.showAvatar,
      isRunEnd: widget.isRunEnd,
      sender: widget.sender,
      fallbackName: message.senderName,
      child: Column(
        crossAxisAlignment:
            widget.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showSender)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                message.senderName,
                style: const TextStyle(
                  color: AppColors.ochre,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Text(
            sticker?.emoji ?? '\u2753',
            style: const TextStyle(fontSize: 64),
          ),
          Text(
            _formatClock(message.createdAt),
            style: TextStyle(
              color: ChatColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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

// Lays a message out beside the sender's profile picture: avatar on the
// left for incoming, on the right for outgoing. When a message isn't the
// last of a run the avatar slot is held open with empty space so every
// bubble in that run stays aligned with the one carrying the face.
class _AvatarRow extends StatelessWidget {
  static const double _avatarRadius = 14;

  final bool mine;
  final bool showAvatar;
  final bool isRunEnd;
  final SocialUser? sender;
  final String fallbackName;
  final Widget child;

  const _AvatarRow({
    required this.mine,
    required this.showAvatar,
    required this.isRunEnd,
    required this.sender,
    required this.fallbackName,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final slot = showAvatar
        ? _ConversationAvatar(
            avatarUrl: sender?.avatarUrl,
            name: sender?.fullName.isNotEmpty == true
                ? sender!.fullName
                : fallbackName,
            radius: _avatarRadius,
            isGroup: false,
          )
        : const SizedBox(width: _avatarRadius * 2);

    return Padding(
      // Tighter spacing inside a run, looser between different speakers,
      // so the conversation has a natural rhythm.
      padding: EdgeInsets.only(bottom: isRunEnd ? 12 : 3),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            slot,
            const SizedBox(width: 8),
          ],
          Flexible(child: child),
        ],
      ),
    );
  }
}

// Profile picture used in the conversation header and beside each
// message. Groups get an icon instead of initials since a group has no
// single face to show.
class _ConversationAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double radius;
  final bool isGroup;

  const _ConversationAvatar({
    required this.avatarUrl,
    required this.name,
    required this.radius,
    required this.isGroup,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final hasImage = avatarUrl != null && avatarUrl!.isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.ochre.withValues(alpha: 0.28),
      // Decode at roughly the drawn size — these repeat down the whole
      // message list, so full-resolution avatars would be pure waste.
      backgroundImage: hasImage
          ? ResizeImage(
              MediaCache.imageProvider(ApiService.resolveUrl(avatarUrl!), cacheWidth: 96),
              width: (radius * 4).round(),
            )
          : null,
      child: hasImage
          ? null
          : isGroup
              ? Icon(Icons.groups_rounded,
                  color: Colors.white, size: radius * 1.1)
              : Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: radius * 0.85,
                  ),
                ),
    );
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
          : MediaCache.imageProvider(ApiService.resolveUrl(user.avatarUrl!), cacheWidth: 96),
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
