import 'package:flutter/material.dart';
import '../Services/api_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// A full-bleed, TikTok-style post: the photo (or a gradient for text-only
/// posts) fills the whole card, caption + author sit bottom-left over a
/// scrim, and like/comment live in a vertical rail on the right — meant to
/// be paged through one-at-a-time (see FeedScreen's vertical PageView),
/// not scrolled as a list.
class PostCard extends StatefulWidget {
  final Post post;
  final String currentUserId;
  final VoidCallback onLike;
  final VoidCallback onOpenComments;
  final double borderRadius;

  const PostCard({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onOpenComments,
    this.borderRadius = 0,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late final AnimationController _burstController;
  late final Animation<double> _burstScale;
  late final Animation<double> _burstOpacity;

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
  }

  @override
  void dispose() {
    _burstController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final liked = widget.post.likes.contains(widget.currentUserId);
    if (!liked) widget.onLike();
    _burstController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final liked = post.likes.contains(widget.currentUserId);
    final hasImage = post.image != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: the post's photo, or a brand-toned gradient for
          // text-only posts so the full-bleed layout still feels intentional.
          if (hasImage)
            Image.network(
              '${ApiService.baseUrl}${post.image}',
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

          // Double-tap to like, with a heart burst — the whole card is the
          // tap target, matching the platform this is modeled on.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
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

          // Caption + author — bottom-left, TikTok-style.
          Positioned(
            left: 16,
            right: 88,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.sandDim,
                      backgroundImage: post.authorAvatar != null
                          ? NetworkImage('${ApiService.baseUrl}${post.authorAvatar}')
                          : null,
                      child: post.authorAvatar == null
                          ? const Icon(Icons.person_rounded,
                              size: 16, color: AppColors.inkSoft)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        post.authorName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
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

          // Action rail — bottom-right, like/comment stacked vertically.
          Positioned(
            right: 12,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
              ],
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
          colors: [AppColors.canopyLight, AppColors.canopy],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.color,
    required this.label,
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
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
            ),
          ),
        ],
      ),
    );
  }
}
