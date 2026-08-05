import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/post_card.dart';
import 'create_post_screen.dart';
import 'post_comments_screen.dart';

class FeedScreen extends StatefulWidget {
  final SessionState session;
  const FeedScreen({super.key, required this.session});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Post> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await ApiService.instance.getPosts();
      setState(() => _posts = posts);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike(Post post) async {
    try {
      final updated = await ApiService.instance.likePost(post.id);
      setState(() {
        _posts = _posts.map((p) => p.id == post.id ? updated : p).toList();
      });
    } catch (_) {
      // Non-critical — swallow and let the user retry the tap.
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.session.currentUser?.id ?? '';

    return Scaffold(
      backgroundColor: AppColors.sand,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPosts,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? EmptyState(
                      icon: Icons.wifi_off_rounded,
                      title: "Can't reach the server",
                      message: _error!,
                      onRetry: _loadPosts,
                    )
                  : _posts.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            EmptyState(
                              icon: Icons.dynamic_feed_rounded,
                              title: 'No posts yet',
                              message:
                                  'Be the first to share something with the community.',
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            return PostCard(
                              post: post,
                              currentUserId: currentUserId,
                              onLike: () => _toggleLike(post),
                              onOpenComments: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        PostCommentsScreen(post: post),
                                  ),
                                );
                                _loadPosts();
                              },
                            );
                          },
                        ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (context) => const CreatePostScreen()),
          );
          if (created == true) _loadPosts();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Post'),
      ),
    );
  }
}
