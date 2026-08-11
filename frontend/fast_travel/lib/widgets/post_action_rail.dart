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

/// The avatar/like/comment/share column for a post. Two looks, matching how
/// TikTok itself splits this between layouts: [dark] (default) is a
/// white-on-video overlay for full-bleed mobile video; dark:false is
/// ink-colored buttons meant to sit in their own panel beside the video,
/// for wide/web layouts where the video isn't full-bleed.
class PostActionRail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final liked = post.likes.contains(currentUserId);
    final iconColor = dark ? Colors.white : AppColors.ink;
    final labelColor = dark ? Colors.white : AppColors.inkSoft;
    final shadows =
        dark ? const [Shadow(blurRadius: 8, color: Colors.black45)] : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailAvatar(
            avatarUrl: post.authorAvatar, name: post.authorName, dark: dark),
        const SizedBox(height: 22),
        _RailButton(
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: liked ? AppColors.clay : iconColor,
          labelColor: labelColor,
          shadows: shadows,
          label: '${post.likes.length}',
          onTap: onLike,
        ),
        const SizedBox(height: 20),
        _RailButton(
          icon: Icons.mode_comment_rounded,
          color: iconColor,
          labelColor: labelColor,
          shadows: shadows,
          label: '${post.comments.length}',
          onTap: onOpenComments,
        ),
        const SizedBox(height: 20),
        _RailButton(
          icon: Icons.reply_rounded,
          color: iconColor,
          labelColor: labelColor,
          shadows: shadows,
          onTap: () => sharePost(context, post),
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color labelColor;
  final List<Shadow>? shadows;
  final String? label;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.color,
    required this.labelColor,
    this.shadows,
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
          Icon(icon, color: color, size: 34, shadows: shadows),
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

  const _RailAvatar(
      {required this.avatarUrl, required this.name, required this.dark});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
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
    );
  }
}
