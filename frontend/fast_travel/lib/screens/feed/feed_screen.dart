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
  // Locally filters the currently-loaded feed. Kept client-side because
  // the posts API doesn't take a query parameter — filtering happens on
  // the already-fetched list rather than round-tripping to the server on
  // every keystroke.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Post> _posts = [];
  bool _loading = true;
  String? _error;
  bool _errorIsNetwork = false;
  int _currentPage = 0;
  String? _openCommentsPostId;
  // Cosmetic only — the backend has no follow-graph, so both tabs show
  // the same posts. Matches TikTok's top tab bar; "For You" is the
  // default like the real app.
  bool _followingSelected = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _searchController.addListener(() {
      final query = _searchController.text.trim();
      if (query == _searchQuery) return;
      setState(() {
        _searchQuery = query;
        // A search that filters out the currently visible page would
        // otherwise leave the PageView pointing at a now-invalid index
        // and render blank until the user scrolls; jump back to the top
        // of the filtered list instead.
        _currentPage = 0;
        _openCommentsPostId = null;
      });
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Case-insensitive substring match against the caption text and the
  // author's name — the two fields a viewer might type to find "beach
  // videos" or "posts by Fatima". Post has no explicit category/tag
  // field, so nothing else to match against.
  List<Post> get _visiblePosts {
    if (_searchQuery.isEmpty) return _posts;
    final needle = _searchQuery.toLowerCase();
    return _posts
        .where((p) =>
            p.text.toLowerCase().contains(needle) ||
            p.authorName.toLowerCase().contains(needle))
        .toList();
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

  // Tapping whichever tab is already selected refreshes and jumps back to
  // the top of the feed — the same gesture TikTok itself uses instead of a
  // dedicated refresh button.
  void _onTabTap(bool followingTapped) {
    if (followingTapped == _followingSelected) {
      _loadPosts();
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      return;
    }
    setState(() => _followingSelected = followingTapped);
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
    for (final p in _visiblePosts) {
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

    final visiblePosts = _visiblePosts;
    final safeCurrentPage = visiblePosts.isEmpty
        ? 0
        : _currentPage.clamp(0, visiblePosts.length - 1);
    final currentPost = isWide && visiblePosts.isNotEmpty
        ? visiblePosts[safeCurrentPage]
        : null;

    final pageView = PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: visiblePosts.length,
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
        final post = visiblePosts[index];
        return Padding(
          padding: isWide
              ? const EdgeInsets.symmetric(vertical: 4)
              : EdgeInsets.zero,
          child: PostCard(
            post: post,
            currentUserId: currentUserId,
            borderRadius: isWide ? 24 : 0,
            isActive: index == safeCurrentPage,
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
      //
      // No SafeArea wrap here either: the whole point of this screen is
      // that the video fills every vertical pixel like TikTok's own feed.
      // The overlaid tab/search/create controls each apply their own
      // SafeArea from inside so they still avoid the status bar/notch.
      body: Stack(
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
                      : visiblePosts.isEmpty
                          // Distinct from the "no posts yet" state above:
                          // the feed does have posts, they just don't
                          // match the current search. Show a message the
                          // user can act on by clearing the query.
                          ? Container(
                              color: AppColors.ink,
                              child: ListView(
                                children: [
                                  const SizedBox(height: 160),
                                  EmptyState(
                                    icon: Icons.search_off_rounded,
                                    title: 'No videos match',
                                    message:
                                        'Nothing found for "$_searchQuery". Try a different search.',
                                    onRetry: () => _searchController.clear(),
                                    retryLabel: 'Clear search',
                                  ),
                                ],
                              ),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
          // Top overlay — TikTok's own header shape: "Following / For
          // You" tabs plus a search bar right underneath, all wrapped
          // in a local SafeArea so they clear the status bar/notch now
          // that AdaptiveShell no longer applies its own SafeArea for
          // this full-bleed screen. The video underneath still fills
          // the full viewport top-to-bottom.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isWide)
                    SizedBox(
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _FeedTab(
                                label: 'Following',
                                selected: _followingSelected,
                                onTap: () => _onTabTap(true),
                              ),
                              const SizedBox(width: 24),
                              _FeedTab(
                                label: 'For You',
                                selected: !_followingSelected,
                                onTap: () => _onTabTap(false),
                              ),
                            ],
                          ),
                          // The old top-right search icon is gone —
                          // the search bar below replaces it, which
                          // is what the "type-to-filter" flow wants.
                          // Discover still lives on its own tab in
                          // the bottom nav for a dedicated browse UI.
                        ],
                      ),
                    ),
                  Padding(
                    // Extra right padding on phones so the search bar
                    // doesn't crash into the round "new post" button
                    // that sits at the same top-right position.
                    padding: EdgeInsets.fromLTRB(12, 6, isWide ? 12 : 56, 6),
                    child: _FeedSearchBar(
                      controller: _searchController,
                      // Wide layouts render on a light "sand" background
                      // (no full-bleed dark video behind), so the pill
                      // needs a light fill to stay readable there.
                      onDark: !isWide,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // "New post" — TikTok's own create button lives in the bottom
          // tab bar rather than floating over the video, but this app's
          // bottom nav is shared across every tab (Discover/Feed/My
          // Trips/Map/Profile), so a Feed-only create button stays here
          // instead of restructuring navigation used by every screen.
          Positioned(
            top: isWide ? 8 : 52,
            right: 8,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: AppColors.ochre,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _createPost,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child:
                        Icon(Icons.add_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The pill-shaped search box sitting under the "Following / For You"
// tabs. Local-only filter: it edits the controller shared with
// _FeedScreenState, which recomputes _visiblePosts on every keystroke.
class _FeedSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool onDark;

  const _FeedSearchBar({required this.controller, required this.onDark});

  @override
  Widget build(BuildContext context) {
    final fill =
        onDark ? Colors.black.withValues(alpha: 0.35) : AppColors.sandDim;
    final foreground = onDark ? Colors.white : AppColors.ink;
    final hint =
        onDark ? Colors.white.withValues(alpha: 0.75) : AppColors.inkSoft;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Container(
          height: 40,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(20),
            border: onDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.25))
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: hint),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: TextStyle(color: foreground, fontSize: 14),
                  cursorColor: AppColors.ochre,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search videos, creators…',
                    hintStyle: TextStyle(color: hint, fontSize: 14),
                  ),
                ),
              ),
              if (value.text.isNotEmpty)
                GestureDetector(
                  onTap: controller.clear,
                  child: Icon(Icons.close_rounded, size: 18, color: hint),
                ),
            ],
          ),
        );
      },
    );
  }
}

// TikTok's own top tab: bold white + a short underline when selected,
// softer/translucent white when not.
class _FeedTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FeedTab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: selected ? FontWeight.bold : FontWeight.w600,
              fontSize: 16,
              shadows: const [Shadow(blurRadius: 8, color: Colors.black45)],
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 2,
            width: selected ? 20 : 0,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}
