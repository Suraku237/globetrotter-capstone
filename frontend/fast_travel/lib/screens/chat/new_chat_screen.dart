import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import 'chat_thread_screen.dart';

/// Picks who to message. Pops `true` if a conversation was actually
/// started (so ChatListScreen knows to refresh), or nothing if the user
/// just backed out.
class NewChatScreen extends StatefulWidget {
  final SessionState session;

  const NewChatScreen({super.key, required this.session});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  List<ChatUser> _users = [];
  List<ChatUser> _filtered = [];
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_filter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await ApiService.instance.getChatUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _filtered = users;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _users
          : _users
              .where((u) => u.fullName.toLowerCase().contains(query))
              .toList();
    });
  }

  Future<void> _selectUser(ChatUser user) async {
    try {
      final convo = await ApiService.instance.startConversation(user.id);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatThreadScreen(
            session: widget.session,
            conversationId: convo.id,
            otherUser: user,
          ),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New message'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search travelers',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.sandDim,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.ochre));
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: "Can't reach the server",
        message: _error!,
        onRetry: _load,
      );
    }
    if (_filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search_rounded,
        title: 'No travelers found',
        message: 'Try a different search.',
      );
    }
    return ListView.builder(
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final user = _filtered[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.sandDim,
            backgroundImage: user.avatarUrl != null
                ? NetworkImage(ApiService.resolveUrl(user.avatarUrl!))
                : null,
            child: user.avatarUrl == null
                ? Text(
                    user.fullName.isNotEmpty
                        ? user.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: AppColors.ink, fontWeight: FontWeight.w700),
                  )
                : null,
          ),
          title: Text(user.fullName),
          onTap: () => _selectUser(user),
        );
      },
    );
  }
}
