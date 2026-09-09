import 'package:flutter/material.dart';
import '../Services/api_service.dart';
import '../Services/live_refresh.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'empty_state.dart';

/// Comments list + input for a single post, shown either as a right-side
/// panel (wide/web layout) or inside a bottom sheet (narrow/mobile) — never
/// as its own screen. Also listens to live updates when on a separate route.
class CommentsPanel extends StatefulWidget {
  final Post post;
  final String currentUserId;
  final ValueChanged<Post> onPostUpdated;
  final VoidCallback? onClose;

  const CommentsPanel({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.onPostUpdated,
    this.onClose,
  });

  @override
  State<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends State<CommentsPanel> {
  final _commentController = TextEditingController();
  bool _sending = false;
  String? _error;
  late Post _post = widget.post;
  late final LiveRefresh _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = LiveRefresh(
      changes: ApiService.instance.changes,
      topics: {'posts'},
      onRefresh: () async {
        try {
          final id = widget.post.id;
          final posts = await ApiService.instance.getPosts();
          if (!mounted || id != widget.post.id) return;
          for (final post in posts) {
            if (post.id == id) {
              setState(() => _post = post);
              break;
            }
          }
        } catch (_) {
          // Keep existing comments and the draft on a failed refresh.
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant CommentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) _post = widget.post;
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final updated =
          await ApiService.instance.addComment(widget.post.id, text);
      if (!mounted) return;
      setState(() => _post = updated);
      widget.onPostUpdated(updated);
      _commentController.clear();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _refresh.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final comments = _post.comments;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Comments (${comments.length})',
                    style: textTheme.titleMedium),
              ),
              if (widget.onClose != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.sandDim),
        Flexible(
          child: comments.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: EmptyState(
                    icon: Icons.mode_comment_outlined,
                    title: 'No comments yet',
                    message: 'Be the first to reply.',
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CommentAvatar(name: comment.authorName),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(comment.authorName,
                                    style: textTheme.titleMedium
                                        ?.copyWith(fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(comment.text, style: textTheme.bodyMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(_error!, style: const TextStyle(color: AppColors.clay)),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                    ),
                    onSubmitted: (_) => _addComment(),
                  ),
                ),
                const SizedBox(width: 8),
                _sending
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : InkWell(
                        onTap: _addComment,
                        customBorder: const CircleBorder(),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: AppColors.ochre,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.send_rounded,
                              size: 20, color: Colors.white),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.sandDim,
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
