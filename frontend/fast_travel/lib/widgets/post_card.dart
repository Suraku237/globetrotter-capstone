import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../Services/api_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'post_action_rail.dart';

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
  // False on wide/web layouts, where FeedScreen renders a PostActionRail
  // of its own beside the (no-longer-full-bleed) video instead of
  // overlaying it on top.
  final bool showActionRail;

  const PostCard({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onOpenComments,
    this.onDelete,
    this.borderRadius = 0,
    this.isActive = true,
    this.showActionRail = true,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
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
    ]).animate(
        CurvedAnimation(parent: _burstController, curve: Curves.easeOut));
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
        content:
            const Text('This removes it for everyone and can\'t be undone.'),
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
    if (confirmed == true) widget.onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
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
                : const _FallbackBackground(buffering: true)
          else if (hasImage)
            Image.network(
              ApiService.resolveUrl(post.image!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const _FallbackBackground(),
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
                      color: Colors.black.withValues(alpha: 0.55),
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
                  final playedFraction = durationMs == 0
                      ? 0.0
                      : (value.position.inMilliseconds / durationMs)
                          .clamp(0.0, 1.0);
                  // How far ahead of playback the video has actually
                  // downloaded — the same "lighter bar ahead of the
                  // playhead" YouTube/Facebook show, so loading is visible
                  // while it's happening instead of just a spinner up
                  // front and nothing after.
                  final bufferedMs = value.buffered.isEmpty
                      ? 0
                      : value.buffered
                          .map((range) => range.end.inMilliseconds)
                          .reduce((a, b) => a > b ? a : b);
                  final bufferedFraction = durationMs == 0
                      ? 0.0
                      : (bufferedMs / durationMs).clamp(0.0, 1.0);
                  return SizedBox(
                    height: 3,
                    child: Stack(
                      children: [
                        const ColoredBox(color: Colors.white24),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: bufferedFraction,
                          child: const ColoredBox(color: Colors.white54),
                        ),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: playedFraction,
                          child: const ColoredBox(color: AppColors.ochre),
                        ),
                      ],
                    ),
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

          // Action rail — bottom-right, overlaid on the video. Hidden on
          // wide/web layouts, where FeedScreen renders one of these beside
          // the (no-longer-full-bleed) video instead.
          if (widget.showActionRail)
            Positioned(
              right: 12,
              bottom: 20,
              child: PostActionRail(
                post: post,
                currentUserId: widget.currentUserId,
                onLike: widget.onLike,
                onOpenComments: widget.onOpenComments,
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
                    color: Colors.black.withValues(alpha: 0.6),
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
  // Shown while a video's controller hasn't finished initializing yet —
  // adds a visible spinner so this reads as "buffering" rather than a
  // stalled/broken card. Not set for text-only or photo posts, which have
  // nothing to wait on.
  final bool buffering;

  const _FallbackBackground({this.buffering = false});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.teal, AppColors.ochre],
        ),
      ),
      child: buffering
          ? const Center(
              child: SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}
