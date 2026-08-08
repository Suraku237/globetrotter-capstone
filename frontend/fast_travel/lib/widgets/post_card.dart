import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../Services/api_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// A full-bleed, TikTok-style post: the photo/video (or a gradient for
/// text-only posts) fills the whole card, caption + author sit bottom-left
/// over a scrim, and like/comment live in a vertical rail on the right —
/// meant to be paged through one-at-a-time (see FeedScreen's vertical
/// PageView), not scrolled as a list.
class PostCard extends StatefulWidget {
  final Post post;
  final String currentUserId;
  final VoidCallback onLike;
  final VoidCallback onOpenComments;
  // Only passed for admins — presence of the callback (not a separate
  // isAdmin flag) is what decides whether the delete control shows at all.
  final VoidCallback? onDelete;
  final double borderRadius;
  // Whether this card is the one currently on-screen in the PageView — a
  // video only plays while its card is active, and pauses otherwise so
  // multiple clips don't play (and play audio) at once.
  final bool isActive;

  const PostCard({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onOpenComments,
    this.onDelete,
    this.borderRadius = 0,
    this.isActive = true,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late final AnimationController _burstController;
  late final Animation<double> _burstScale;
  late final Animation<double> _burstOpacity;

  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _burstScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _burstController, curve: Curves.easeOut));
    _burstOpacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 45),
    ]).animate(_burstController);
    _initVideo();
  }

  void _initVideo() {
    final video = widget.post.video;
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
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _videoController?.dispose();
      _videoController = null;
      _initVideo();
      return;
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.isActive && !oldWidget.isActive) {
      controller.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      controller.pause();
    }
  }

  @override
  void dispose() {
    _burstController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final liked = widget.post.likes.contains(widget.currentUserId);
    if (!liked) widget.onLike();
    _burstController.forward(from: 0);
  }

  void _togglePlayPause() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  Future<void> _confirmDelete() async {
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
    if (confirmed == true) widget.onDelete?.call();
  }

  Future<void> _share() async {
    final post = widget.post;
    final mediaPath = post.video ?? post.image;
    final link = mediaPath != null
        ? ApiService.resolveUrl(mediaPath)
        : 'Fast Travel — a post by ${post.authorName}';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final liked = post.likes.contains(widget.currentUserId);
    final hasImage = post.image != null;
    final hasVideo = post.video != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: the post's video, photo, or a brand-toned gradient
          // for text-only posts so the full-bleed layout still feels
          // intentional.
          if (hasVideo)
            (_videoController != null && _videoController!.value.isInitialized)
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController!.value.size.width,
                      height: _videoController!.value.size.height,
                      child: VideoPlayer(_videoController!),
                    ),
                  )
                : const _FallbackBackground()
          else if (hasImage)
            Image.network(
              ApiService.resolveUrl(post.image!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const _FallbackBackground(),
            )
          else
            const _FallbackBackground(),

          // Legibility scrim behind the caption/author block.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.55, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),

          // Single tap pauses/resumes video; double-tap likes with a heart
          // burst — the whole card is the tap target either way.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: hasVideo ? _togglePlayPause : null,
              onDoubleTap: _handleDoubleTap,
            ),
          ),

          Center(
            child: FadeTransition(
              opacity: _burstOpacity,
              child: ScaleTransition(
                scale: _burstScale,
                child: const Icon(Icons.favorite_rounded,
                    color: Colors.white, size: 96),
              ),
            ),
          ),

          // Paused indicator — only visible while a video is paused, so a
          // single tap always has a clear play-again affordance.
          if (hasVideo &&
              _videoController != null &&
              _videoController!.value.isInitialized)
            Center(
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _videoController!,
                builder: (context, value, _) => AnimatedOpacity(
                  opacity: value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 48),
                  ),
                ),
              ),
            ),

          // Video progress bar — pinned to the very bottom edge, above the
          // scrim so it stays legible against both light and dark frames.
          if (hasVideo &&
              _videoController != null &&
              _videoController!.value.isInitialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _videoController!,
                builder: (context, value, _) {
                  final durationMs = value.duration.inMilliseconds;
                  final progress = durationMs == 0
                      ? 0.0
                      : (value.position.inMilliseconds / durationMs)
                          .clamp(0.0, 1.0);
                  return LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.ochre),
                  );
                },
              ),
            ),

          // Caption + author — bottom-left, TikTok-style (avatar lives in
          // the action rail, matching the reference layout, not here).
          Positioned(
            left: 16,
            right: 88,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  post.authorName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  post.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Action rail — bottom-right, TikTok order: avatar, like,
          // comment, share.
          Positioned(
            right: 12,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailAvatar(
                  avatarUrl: post.authorAvatar,
                  name: post.authorName,
                ),
                const SizedBox(height: 22),
                _RailButton(
                  icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? AppColors.clay : Colors.white,
                  label: '${post.likes.length}',
                  onTap: widget.onLike,
                ),
                const SizedBox(height: 20),
                _RailButton(
                  icon: Icons.mode_comment_rounded,
                  color: Colors.white,
                  label: '${post.comments.length}',
                  onTap: widget.onOpenComments,
                ),
                const SizedBox(height: 20),
                _RailButton(
                  icon: Icons.reply_rounded,
                  color: Colors.white,
                  onTap: _share,
                ),
              ],
            ),
          ),

          if (widget.onDelete != null)
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: _confirmDelete,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FallbackBackground extends StatelessWidget {
  const _FallbackBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.teal, AppColors.ochre],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? label;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.color,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 34, shadows: const [
            Shadow(blurRadius: 8, color: Colors.black45),
          ]),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RailAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;

  const _RailAvatar({required this.avatarUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: CircleAvatar(
        backgroundColor: AppColors.sandDim,
        backgroundImage:
            avatarUrl != null ? NetworkImage(ApiService.resolveUrl(avatarUrl!)) : null,
        child: avatarUrl == null
            ? Text(
                initial,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              )
            : null,
      ),
    );
  }
}
