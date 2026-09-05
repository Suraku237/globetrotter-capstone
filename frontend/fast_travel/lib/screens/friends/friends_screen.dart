import 'dart:async';

import 'package:flutter/material.dart';

import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

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
          ? await ApiService.instance.sendGroupMessage(widget.group!.id, text)
          : await ApiService.instance
              .sendDirectMessage(widget.friend!.id, text);
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
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Write a message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final SocialMessage message;
  final bool mine;
  final bool showSender;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showSender,
  });

  @override
  Widget build(BuildContext context) {
    final color = mine ? AppColors.ochre : AppColors.sand;
    final textColor = mine ? Colors.white : AppColors.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
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
            if (showSender && !mine)
              Text(message.senderName,
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            Text(message.text, style: TextStyle(color: textColor)),
          ],
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
