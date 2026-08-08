import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../Services/api_service.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';

// Opens on the tapped post but lets the user swipe vertically through every
// post in the feed (same gesture as the feed itself), instead of being
// locked to a single post's comments.
class PostCommentsScreen extends StatefulWidget {
  final List<Post> posts;
  final int initialIndex;
  final String currentUserId;
  final bool isAdmin;
  const PostCommentsScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    required this.currentUserId,
    this.isAdmin = false,
  });

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late int _currentIndex = widget.initialIndex;
  bool _deleting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final post = widget.posts[_currentIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text('This removes it for everyone and can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.clay)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await ApiService.instance.deletePost(post.id);
      // Simplest consistent option: the feed already reloads its post list
      // when this screen is popped, so just leave rather than try to
      // mutate the (immutable) posts list mid-PageView.
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this post.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sand,
      appBar: AppBar(
        title: Text('Post ${_currentIndex + 1} of ${widget.posts.length}'),
        actions: [
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Delete post',
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline_rounded,
                      color: AppColors.clay),
              onPressed: _deleting ? null : _confirmDelete,
            ),
        ],
      ),
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: widget.posts.length,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          itemBuilder: (context, index) {
            final post = widget.posts[index];
            return _PostDetailPage(
              key: ValueKey(post.id),
              post: post,
              currentUserId: widget.currentUserId,
              isActive: index == _currentIndex,
            );
          },
        ),
      ),
    );
  }
}

class _PostDetailPage extends StatefulWidget {
  final Post post;
  final String currentUserId;
  final bool isActive;
  const _PostDetailPage({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.isActive,
  });

  @override
  State<_PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<_PostDetailPage> {
  late Post _post;
  final _commentController = TextEditingController();
  VideoPlayerController? _videoController;
  bool _sending = false;
  bool _liking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _initVideo();
  }

  void _initVideo() {
    final video = _post.video;
    if (video == null) return;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(ApiService.resolveUrl(video)),
    );
    _videoController = controller;
    controller.setLooping(true);
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      if (widget.isActive) controller.play();
    });
  }

  @override
  void didUpdateWidget(covariant _PostDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.isActive && !oldWidget.isActive) {
      controller.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      controller.pause();
    }
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);
    try {
      final updated = await ApiService.instance.likePost(_post.id);
      if (mounted) setState(() => _post = updated);
    } catch (_) {
      // Non-critical — swallow and let the user retry the tap.
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final updated = await ApiService.instance.addComment(_post.id, text);
      setState(() {
        _post = updated;
        _commentController.clear();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasImage = _post.image != null;
    final hasVideo = _post.video != null;
    final liked = _post.likes.contains(widget.currentUserId);

    return Column(
      children: [
        if (hasImage || hasVideo)
          SizedBox(
            height: 300,
            width: double.infinity,
            child: hasVideo
                ? (_videoController != null &&
                        _videoController!.value.isInitialized)
                    ? FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _videoController!.value.size.width,
                          height: _videoController!.value.size.height,
                          child: VideoPlayer(_videoController!),
                        ),
                      )
                    : const ColoredBox(color: AppColors.canopy)
                : Image.network(
                    ApiService.resolveUrl(_post.image!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(color: AppColors.canopy),
                  ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AuthorAvatar(
                avatarUrl: _post.authorAvatar,
                name: _post.authorName,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_post.authorName, style: textTheme.titleMedium),
                    if (_post.text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(_post.text, style: textTheme.bodyLarge),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _toggleLike,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 4),
                            child: Row(
                              children: [
                                Icon(
                                  liked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 20,
                                  color:
                                      liked ? AppColors.clay : AppColors.inkSoft,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_post.likes.length}',
                                  style: textTheme.labelLarge?.copyWith(
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        const Icon(Icons.mode_comment_outlined,
                            size: 19, color: AppColors.inkSoft),
                        const SizedBox(width: 6),
                        Text(
                          '${_post.comments.length}',
                          style: textTheme.labelLarge
                              ?.copyWith(color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.sandDim),
        Expanded(
          child: _post.comments.isEmpty
              ? const EmptyState(
                  icon: Icons.mode_comment_outlined,
                  title: 'No comments yet',
                  message: 'Be the first to reply.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _post.comments.length,
                  itemBuilder: (context, index) {
                    final comment = _post.comments[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AuthorAvatar(name: comment.authorName, size: 32),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                              size: 20, color: AppColors.ink),
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

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({this.avatarUrl, required this.name, this.size = 40});

  final String? avatarUrl;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.sandDim,
      backgroundImage:
          avatarUrl != null ? NetworkImage(ApiService.resolveUrl(avatarUrl!)) : null,
      child: avatarUrl == null
          ? Text(
              initial,
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
              ),
            )
          : null,
    );
  }
}
