import 'package:flutter/material.dart';
import '../Services/api_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final String currentUserId;
  final VoidCallback onLike;
  final VoidCallback onOpenComments;

  const PostCard({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onOpenComments,
  });

  @override
  Widget build(BuildContext context) {
    final liked = post.likes.contains(currentUserId);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.sandDim,
                  backgroundImage: post.authorAvatar != null
                      ? NetworkImage('${ApiService.baseUrl}${post.authorAvatar}')
                      : null,
                  child: post.authorAvatar == null
                      ? const Icon(Icons.person_rounded,
                          size: 18, color: AppColors.inkSoft)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(post.authorName,
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(post.text, style: Theme.of(context).textTheme.bodyLarge),
            if (post.image != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  '${ApiService.baseUrl}${post.image}',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 220,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 220,
                    color: AppColors.sandDim,
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_not_supported_rounded,
                        color: AppColors.inkSoft),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onLike,
                  icon: Icon(
                    liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: liked ? AppColors.clay : AppColors.inkSoft,
                  ),
                  label: Text('${post.likes.length}'),
                ),
                TextButton.icon(
                  onPressed: onOpenComments,
                  icon: const Icon(Icons.mode_comment_outlined,
                      color: AppColors.inkSoft),
                  label: Text('${post.comments.length}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
