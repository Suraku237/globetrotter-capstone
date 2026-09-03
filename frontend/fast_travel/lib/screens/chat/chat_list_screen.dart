import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import 'community_room_screen.dart';
import 'chat_thread_screen.dart';
import 'new_chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final SessionState session;

  const ChatListScreen({super.key, required this.session});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatConversation> _conversations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversations = await ApiService.instance.getConversations();
      if (!mounted) return;
      setState(() => _conversations = conversations);
    } on ApiException catch (e) {
      if (e.isUnauthorized) return;
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startNewConversation() async {
    final started = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (context) => NewChatScreen(session: widget.session)),
    );
    if (started == true) _load();
  }

  Future<void> _openCommunityRoom() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CommunityRoomScreen(session: widget.session),
      ),
    );
  }

  Future<void> _openThread(ChatConversation convo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatThreadScreen(
          session: widget.session,
          conversationId: convo.id,
          otherUser: convo.otherUser,
        ),
      ),
    );
    // Read/unread counts and the last-message preview may have changed
    // while the thread was open.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'Community room',
            icon: const Icon(Icons.public_rounded),
            onPressed: _openCommunityRoom,
          ),
          IconButton(
            tooltip: 'New message',
            icon: const Icon(Icons.add_comment_rounded),
            onPressed: _startNewConversation,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _conversations.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.ochre));
    }
    if (_error != null && _conversations.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Can't reach the server",
            message: _error!,
            onRetry: _load,
          ),
        ],
      );
    }
    if (_conversations.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'No messages yet',
            message: 'Start a conversation with another traveler.',
            onRetry: _startNewConversation,
            retryLabel: 'New message',
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: _conversations.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
      itemBuilder: (context, index) {
        final convo = _conversations[index];
        return _ConversationTile(
          conversation: convo,
          onTap: () => _openThread(convo),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  String _preview(ChatMessage? message) {
    if (message == null) return 'Say hello 👋';
    switch (message.type) {
      case 'audio':
        return '🎤 Voice message';
      case 'sticker':
        return '${message.sticker} Sticker';
      default:
        return message.text ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = conversation.otherUser;
    final unread = conversation.unreadCount > 0;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: AppColors.sandDim,
        backgroundImage: other?.avatarUrl != null
            ? NetworkImage(ApiService.resolveUrl(other!.avatarUrl!))
            : null,
        child: other?.avatarUrl == null
            ? Text(
                (other?.fullName.isNotEmpty ?? false)
                    ? other!.fullName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: AppColors.ink, fontWeight: FontWeight.w700),
              )
            : null,
      ),
      title: Text(
        other?.fullName ?? 'Unknown traveler',
        style: TextStyle(
          fontWeight: unread ? FontWeight.bold : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        _preview(conversation.lastMessage),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: unread ? AppColors.ink : AppColors.inkSoft,
          fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: unread
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.ochre,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }
}
