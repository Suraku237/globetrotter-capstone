import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../Services/api_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

Future<void> sharePost(BuildContext context, Post post) async {
  final mediaPath = post.video ?? post.image;
  final link = mediaPath != null
      ? ApiService.resolveUrl(mediaPath)
      : 'Fast Travel — a post by ${post.authorName}';
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Link copied to clipboard')),
  );
}

/// The avatar/like/comment/bookmark/share column for a post — laid out to
/// match TikTok's own rail: avatar with a small follow badge, then like,
/// comment, bookmark and share as bare icon+count pairs (a text shadow for
/// legibility, no backing circle), and a spinning "sound" disc at the very
/// bottom. Two looks: [dark] (default) is the white-on-video overlay for
/// full-bleed mobile video; dark:false is ink-colored, meant to sit in its
/// own panel beside the video, for wide/web layouts where the video isn't
/// full-bleed.
class PostActionRail extends StatefulWidget {
  final Post post;
  final String currentUserId;
  final VoidCallback onLike;
  final VoidCallback onOpenComments;
  final bool dark;

  const PostActionRail({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onOpenComments,
    this.dark = true,
  });

  @override
  State<PostActionRail> createState() => _PostActionRailState();
}

class _PostActionRailState extends State<PostActionRail> {
  // Bookmark has no backend field to persist to (Post carries no "saves"
  // list), so this is a local, session-only toggle — same reason it shows
  // no count, rather than a number that would silently reset on reload.
  bool _saved = false;
  // Same story: no follow-graph in the backend, so this is a visual-only
  // toggle matching TikTok's badge, not a real follow relationship.
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final dark = widget.dark;
    final liked = post.likes.contains(widget.currentUserId);
    final iconColor = dark ? Colors.white : AppColors.ink;
    final labelColor = dark ? Colors.white : AppColors.inkSoft;
    final shadows =
        dark ? const [Shadow(blurRadius: 8, color: Colors.black45)] : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailAvatar(
          avatarUrl: post.authorAvatar,
          name: post.authorName,
          dark: dark,
          following: _following,
          onFollowTap: () => setState(() => _following = !_following),
        ),
        const SizedBox(height: 22),
        _RailButton(
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: liked ? AppColors.clay : iconColor,
          labelColor: labelColor,
          shadows: shadows,
          label: '${post.likes.length}',
          onTap: widget.onLike,
        ),
        const SizedBox(height: 20),
        _RailButton(
          icon: Icons.mode_comment_rounded,
          color: iconColor,
          labelColor: labelColor,
          shadows: shadows,
          label: '${post.comments.length}',
          onTap: widget.onOpenComments,
        ),
        const SizedBox(height: 20),
        _RailButton(
          icon: _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          color: _saved ? AppColors.ochre : iconColor,
          labelColor: labelColor,
          shadows: shadows,
          onTap: () => setState(() => _saved = !_saved),
        ),
        const SizedBox(height: 20),
        _RailButton(
          // Flipped so the arrow curls to the right, like TikTok's share
          // icon, instead of Material's default left-curling reply arrow.
          icon: Icons.reply_rounded,
          flip: true,
          color: iconColor,
          labelColor: labelColor,
          shadows: shadows,
          onTap: () => sharePost(context, post),
        ),
        const SizedBox(height: 20),
        _SoundDisc(avatarUrl: post.authorAvatar, dark: dark),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final bool flip;
  final Color color;
  final Color labelColor;
  final List<Shadow>? shadows;
  final String? label;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    this.flip = false,
    required this.color,
    required this.labelColor,
    this.shadows,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(icon, color: color, size: 32, shadows: shadows);
    if (flip) {
      iconWidget = Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(math.pi),
        child: iconWidget,
      );
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: TextStyle(
                color: labelColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: shadows,
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
  final bool dark;
  final bool following;
  final VoidCallback onFollowTap;

  const _RailAvatar({
    required this.avatarUrl,
    required this.name,
    required this.dark,
    required this.following,
    required this.onFollowTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return SizedBox(
      // A little taller/wider than the avatar itself so the follow badge
      // (bottom-center, overlapping the avatar's edge) has room without
      // getting clipped.
      width: 44,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: dark ? Colors.white : AppColors.sandDim,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              backgroundColor: AppColors.sandDim,
              backgroundImage: avatarUrl != null
                  ? NetworkImage(ApiService.resolveUrl(avatarUrl!))
                  : null,
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
          ),
          if (!following)
            Positioned(
              bottom: 0,
              child: GestureDetector(
                onTap: onFollowTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.clay,
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The small spinning "sound" disc TikTok anchors at the bottom of the
/// rail — here just a generic music note on the post's own thumbnail
/// (there's no separate audio-track metadata to show), continuously
/// rotating while the card is on screen.
class _SoundDisc extends StatefulWidget {
  final String? avatarUrl;
  final bool dark;

  const _SoundDisc({required this.avatarUrl, required this.dark});

  @override
  State<_SoundDisc> createState() => _SoundDiscState();
}

class _SoundDiscState extends State<_SoundDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.ink,
          border: Border.all(color: Colors.white, width: 2),
          image: widget.avatarUrl != null
              ? DecorationImage(
                  image: NetworkImage(ApiService.resolveUrl(widget.avatarUrl!)),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        alignment: Alignment.center,
        child: widget.avatarUrl == null
            ? const Icon(Icons.music_note_rounded,
                color: Colors.white, size: 16)
            : null,
      ),
    );
  }
}
