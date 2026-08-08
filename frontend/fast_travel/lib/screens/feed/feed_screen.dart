import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/post_card.dart';
import 'create_post_screen.dart';
import 'post_comments_screen.dart';

// Above this width the one-post-at-a-time feed switches from edge-to-edge
// (phones) to a centered, rounded "phone frame" — full-bleed vertical video
// styling doesn't read well stretched across a desktop window.
const double _kWideBreakpoint = 700;

class FeedScreen extends StatefulWidget {
  final SessionState session;
  const FeedScreen({super.key, required this.session});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final PageController _pageController = PageController();
  List<Post> _posts = [];
  bool _loading = true;
  String? _error;
  bool _errorIsNetwork = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorIsNetwork = false;
    });
    try {
      final posts = await ApiService.instance.getPosts();
      setState(() => _posts = posts);
    } on ApiException catch (e) {
      // A 401 signs the user out and returns them to the login screen (see
      // ApiService.onUnauthorized in main.dart) — nothing to show here.
      if (e.isUnauthorized) return;
      setState(() {
        _error = e.message;
        _errorIsNetwork = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Could not reach the server.';
        _errorIsNetwork = true;
      });
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
    final isWide = MediaQuery.sizeOf(context).width >= _kWideBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.sand,
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          IconButton(
            tooltip: 'New post',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () async {
              final created = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (context) => const CreatePostScreen()),
              );
              if (created == true) _loadPosts();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPosts,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.ochre))
              : _error != null
                  ? EmptyState(
                      icon: _errorIsNetwork
                          ? Icons.wifi_off_rounded
                          : Icons.error_outline_rounded,
                      title: _errorIsNetwork
                          ? "Can't reach the server"
                          : 'Something went wrong',
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
                      : Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: isWide ? 430 : double.infinity,
                            ),
                            child: Padding(
                              padding: isWide
                                  ? const EdgeInsets.symmetric(vertical: 24)
                                  : EdgeInsets.zero,
                              child: PageView.builder(
                                controller: _pageController,
                                scrollDirection: Axis.vertical,
                                itemCount: _posts.length,
                                onPageChanged: (index) =>
                                    setState(() => _currentPage = index),
                                itemBuilder: (context, index) {
                                  final post = _posts[index];
                                  return Padding(
                                    padding: isWide
                                        ? const EdgeInsets.symmetric(vertical: 4)
                                        : EdgeInsets.zero,
                                    child: PostCard(
                                      post: post,
                                      currentUserId: currentUserId,
                                      borderRadius: isWide ? 24 : 0,
                                      isActive: index == _currentPage,
                                      onLike: () => _toggleLike(post),
                                      onOpenComments: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => PostCommentsScreen(
                                              posts: _posts,
                                              initialIndex: index,
                                              currentUserId: currentUserId,
                                            ),
                                          ),
                                        );
                                        _loadPosts();
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
        ),
      ),
    );
  }
}
