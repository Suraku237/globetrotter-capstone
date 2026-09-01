import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/comments_panel.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/post_action_rail.dart';
import '../../widgets/post_card.dart';
import 'create_post_screen.dart';

// Matches AdaptiveShell's own breakpoint (NavigationBar -> NavigationRail)
// so the whole app switches from "phone" to "wide" layout at exactly the
// same width, instead of the nav rail appearing while Feed is still in
// full-bleed phone mode. Above this width the one-post-at-a-time feed
// switches from edge-to-edge (phones) to a centered, rounded "phone
// frame" — full-bleed vertical video styling doesn't read well stretched
// across a tablet/desktop window. Comments also switch presentation at
// this point: a side panel next to the post on wide/web layouts, a
// bottom sheet on narrow ones — never a separate screen.
const double _kWideBreakpoint = 600;

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
  String? _openCommentsPostId;

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
      _updatePost(updated);
    } catch (_) {
      // Non-critical — swallow and let the user retry the tap.
    }
  }

  Future<void> _deletePost(Post post) async {
    try {
      await ApiService.instance.deletePost(post.id);
      setState(() {
        _posts = _posts.where((p) => p.id != post.id).toList();
        if (_openCommentsPostId == post.id) _openCommentsPostId = null;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this post.')),
        );
      }
    }
  }

  void _updatePost(Post updated) {
    setState(() {
      _posts = _posts.map((p) => p.id == updated.id ? updated : p).toList();
    });
  }

  Post? get _openPost {
    final id = _openCommentsPostId;
    if (id == null) return null;
    for (final p in _posts) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _openComments(Post post,
      {required bool isWide, required String currentUserId}) {
    if (isWide) {
      setState(() {
        _openCommentsPostId = _openCommentsPostId == post.id ? null : post.id;
      });
      return;
    }
    // Narrow screens: a full-screen page rather than a partial-height
    // bottom sheet — comments get the whole screen to work with instead
    // of being squeezed into the bottom 70% of it.
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => Scaffold(
          backgroundColor: AppColors.sand,
          appBar: AppBar(
            backgroundColor: AppColors.sand,
            title: const Text('Comments'),
          ),
          body: CommentsPanel(
            post: post,
            currentUserId: currentUserId,
            onPostUpdated: _updatePost,
            onClose: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
  }

  Future<void> _createPost() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const CreatePostScreen()),
    );
    if (created == true) _loadPosts();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.session.currentUser?.id ?? '';
    final isAdmin = widget.session.currentUser?.role == 'admin';
    final isWide = MediaQuery.sizeOf(context).width >= _kWideBreakpoint;
    final openPost = isWide ? _openPost : null;

    final currentPost =
        isWide && _posts.isNotEmpty ? _posts[_currentPage] : null;

    final pageView = PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: _posts.length,
      // NOTE: allowImplicitScrolling: true was tried here to preload the
      // next video's controller ahead of a swipe, but a vertical PageView
      // with that flag inside this screen's constrained-width wide-layout
      // (ConstrainedBox + Row below) crashes the renderer — "RenderViewport
      // ... w<=Infinity" / "Cannot hit test a render box with no size".
      // Not worth it: a crash is worse than a cold-start buffer on swipe.
      onPageChanged: (index) => setState(() {
        _currentPage = index;
        _openCommentsPostId = null;
      }),
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
            // On wide/web layouts the rail is rendered as its own panel
            // beside the video instead (see build() below) — the video
            // itself no longer needs to be full-bleed there.
            showActionRail: !isWide,
            onLike: () => _toggleLike(post),
            onDelete: isAdmin ? () => _deletePost(post) : null,
            onOpenComments: () => _openComments(
              post,
              isWide: isWide,
              currentUserId: currentUserId,
            ),
          ),
        );
      },
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      // No AppBar here — AdaptiveShell already renders the "Feed" title;
      // a second one here would show it twice. The "new post" button lives
      // as a small overlay at the top-right of the body instead (below)
      // rather than a bottom-right FAB, which used to sit right on top of
      // the action rail's like/comment/share buttons on narrow screens.
      body: SafeArea(
        child: Stack(
          children: [
            // NOTE: deliberately NOT wrapped in a RefreshIndicator. A
            // RefreshIndicator and a vertical PageView both claim vertical
            // drag gestures, and nesting them here is what made the swipe
            // feel "broken" — a swipe between videos would sometimes get
            // eaten by the refresh gesture recognizer instead of paging,
            // or the refresh spinner would pop in over a video mid-swipe.
            // Pull-to-refresh isn't essential for a paged feed anyway
            // (there's no "top of a list" to pull down from once you're
            // past the first video) — a manual refresh action in the
            // corner (below) replaces it without the gesture conflict.
            _loading
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
                            children: [
                              const SizedBox(height: 120),
                              EmptyState(
                                icon: Icons.dynamic_feed_rounded,
                                title: 'No posts yet',
                                message:
                                    'Be the first to share something with the community.',
                                onRetry: _loadPosts,
                                retryLabel: 'Refresh',
                              ),
                            ],
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              // Wide/web: size the video card off actual
                              // available space (like TikTok's desktop video
                              // panel) instead of a fixed narrow width that
                              // leaves most of the window empty. Bounded by
                              // whatever room is actually left over once the
                              // rail and (if open) the comments panel take
                              // their share, so it fills the rest without
                              // overflowing past them.
                              const railColumnWidth = 96.0;
                              final commentsColumnWidth =
                                  openPost != null ? 380.0 + 16.0 : 0.0;
                              final reserved = (currentPost != null
                                      ? railColumnWidth
                                      : 0.0) +
                                  commentsColumnWidth;
                              final maxWidthFromSpace =
                                  (constraints.maxWidth - reserved)
                                      .clamp(320.0, 640.0);

                              final cardHeight = (constraints.maxHeight - 48)
                                  .clamp(320.0, 900.0);
                              final cardWidth = isWide
                                  ? (cardHeight * 9 / 16)
                                      .clamp(320.0, maxWidthFromSpace)
                                  : double.infinity;

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ConstrainedBox(
                                    constraints:
                                        BoxConstraints(maxWidth: cardWidth),
                                    child: Padding(
                                      padding: isWide
                                          ? const EdgeInsets.symmetric(
                                              vertical: 24)
                                          : EdgeInsets.zero,
                                      child: pageView,
                                    ),
                                  ),
                                  if (currentPost != null) ...[
                                    const SizedBox(width: 12),
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 20),
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: PostActionRail(
                                          post: currentPost,
                                          currentUserId: currentUserId,
                                          dark: false,
                                          onLike: () =>
                                              _toggleLike(currentPost),
                                          onOpenComments: () => _openComments(
                                            currentPost,
                                            isWide: isWide,
                                            currentUserId: currentUserId,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (openPost != null) ...[
                                    const SizedBox(width: 16),
                                    SizedBox(
                                      width: 380,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 24),
                                        child: Material(
                                          color: Colors.white,
                                          elevation: 3,
                                          shadowColor: AppColors.ink
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          clipBehavior: Clip.antiAlias,
                                          child: CommentsPanel(
                                            post: openPost,
                                            currentUserId: currentUserId,
                                            onPostUpdated: _updatePost,
                                            onClose: () => setState(() =>
                                                _openCommentsPostId = null),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
            // Small top-right "new post" + refresh buttons — replaces the
            // old bottom-right FAB, which used to land right on top of the
            // action rail's like/comment/share buttons on narrow screens.
            // Refresh moved here (instead of RefreshIndicator's pull
            // gesture) since it no longer competes with the PageView for
            // vertical swipes.
            Positioned(
              top: 8,
              right: 8,
              child: Column(
                children: [
                  Material(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _loading ? null : _loadPosts,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: AppColors.ochre,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _createPost,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.add_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
