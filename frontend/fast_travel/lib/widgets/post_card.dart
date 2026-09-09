import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../Services/api_service.dart';
import '../Services/media_cache.dart';
import '../Services/media_playback.dart';
import '../Services/media_settings.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'post_action_rail.dart';
import 'public_network_image.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _burstController;
  late final Animation<double> _burstScale;
  late final Animation<double> _burstOpacity;

  VideoPlayerController? _videoController;
  Timer? _initializationTimeout;
  bool _initializing = false;
  bool _videoFailed = false;
  bool _userRequestedPlay = false;
  bool _userPaused = false;
  bool _visible = false;
  bool _foreground = true;

  bool get _canPlay =>
      widget.isActive &&
      _visible &&
      _foreground &&
      !MediaPlayback.suspended.value;

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
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    MediaSettings.instance.addListener(_settingsChanged);
    MediaPlayback.suspended.addListener(_syncPlayback);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.of(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _syncPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  void _settingsChanged() {
    if (MediaSettings.instance.dataSaver && !_userRequestedPlay) {
      _releaseVideo();
      if (mounted) setState(() {});
    }
    _syncPlayback();
  }

  void _releaseVideo() {
    _initializationTimeout?.cancel();
    final controller = _videoController;
    _videoController = null;
    _initializing = false;
    controller?.removeListener(_videoChanged);
    if (controller != null) unawaited(controller.dispose());
  }

  void _videoChanged() {
    final controller = _videoController;
    if (controller == null || !controller.value.hasError || _videoFailed) return;
    setState(() {
      _videoFailed = true;
      _initializing = false;
    });
  }

  void _syncPlayback() {
    if (!mounted) return;
    final controller = _videoController;
    if (!_canPlay || _userPaused) {
      if (_initializing && MediaSettings.instance.dataSaver) {
        _releaseVideo();
        _userRequestedPlay = false;
        return;
      }
      if (controller?.value.isInitialized == true) {
        unawaited(controller!.pause());
      }
      return;
    }
    if (_videoFailed) return;
    if (controller == null) {
      if (_userRequestedPlay || !MediaSettings.instance.dataSaver) {
        unawaited(_initVideo());
      }
    } else if (controller.value.isInitialized) {
      unawaited(_play(controller));
    }
  }

  Future<void> _play(VideoPlayerController controller) async {
    try {
      await controller.play();
    } on PlatformException {
      if (mounted && identical(controller, _videoController)) {
        setState(() => _videoFailed = true);
      }
    }
  }

  Future<void> _initVideo() async {
    final video = widget.post.video;
    if (video == null || _initializing || !_canPlay) return;
    // initialize() itself downloads video bytes: do not even create the
    // controller until the user requests playback (or opts out of Data Saver).
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(ApiService.resolveUrl(video)),
    );
    _videoController = controller;
    controller.addListener(_videoChanged);
    setState(() {
      _initializing = true;
      _videoFailed = false;
    });
    final deadline = Timer(const Duration(seconds: 30), () {
      if (!mounted || !identical(controller, _videoController)) return;
      _releaseVideo();
      setState(() => _videoFailed = true);
    });
    _initializationTimeout = deadline;
    try {
      await controller.initialize();
      if (!mounted || !identical(controller, _videoController)) return;
      await controller.setLooping(true);
      if (!mounted || !identical(controller, _videoController)) return;
      setState(() => _initializing = false);
      if (_canPlay && !_userPaused) await _play(controller);
    } on PlatformException {
      if (!mounted || !identical(controller, _videoController)) return;
      setState(() {
        _initializing = false;
        _videoFailed = true;
      });
    } finally {
      deadline.cancel();
    }
  }

  void _startVideo() {
    if (!_canPlay || _initializing) return;
    setState(() {
      _userRequestedPlay = true;
      _userPaused = false;
      _videoFailed = false;
    });
    _releaseVideo();
    unawaited(_initVideo());
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.video != widget.post.video) {
      _releaseVideo();
      _userRequestedPlay = false;
      _userPaused = false;
      _videoFailed = false;
    }
    _syncPlayback();
  }

  @override
  void dispose() {
    _burstController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    MediaSettings.instance.removeListener(_settingsChanged);
    MediaPlayback.suspended.removeListener(_syncPlayback);
    _releaseVideo();
    super.dispose();
  }

  void _handleDoubleTap() {
    final liked = widget.post.likes.contains(widget.currentUserId);
    if (!liked) widget.onLike();
    _burstController.forward(from: 0);
  }

  void _togglePlayPause() {
    if (!_canPlay) return;
    final controller = _videoController;
    if (controller == null || _videoFailed) {
      _startVideo();
      return;
    }
    if (!controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      _userPaused = true;
      unawaited(controller.pause());
    } else {
      _userRequestedPlay = true;
      _userPaused = false;
      unawaited(_play(controller));
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
    // Size raster decode to the actual on-screen pixel budget so phones
    // don't waste memory (and decode time) unpacking a 4000×3000 JPEG
    // just to draw it into a card that's ~400px wide. Falls back to a
    // sensible cap if the widget hasn't been laid out yet.
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final mediaSize = MediaQuery.of(context).size;
    final targetLogicalWidth = mediaSize.shortestSide.clamp(320.0, 720.0);
    final targetLogicalHeight = mediaSize.longestSide.clamp(480.0, 1280.0);
    final cacheWidthPx = (targetLogicalWidth * devicePixelRatio).round();
    final cacheHeightPx = (targetLogicalHeight * devicePixelRatio).round();

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
                : _FallbackBackground(buffering: _initializing)
          else if (hasImage)
            PublicNetworkImage(
              ApiService.resolveUrl(post.image!),
              fit: BoxFit.cover,
              // Decode at roughly the card's own pixel size instead of
              // the source image's native resolution — a 12MP camera
              // photo would otherwise chew ~50MB of RAM per card on a
              // phone just to be drawn 400px wide.
              cacheWidth: cacheWidthPx,
              cacheHeight: cacheHeightPx,
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

          if (hasVideo &&
              (_videoController == null || _videoFailed || _initializing))
            Center(
              child: _initializing
                  ? const SizedBox.shrink()
                  : TextButton.icon(
                      key: const ValueKey('video-play'),
                      onPressed: _canPlay ? _startVideo : null,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.black54,
                      ),
                      icon: Icon(_videoFailed
                          ? Icons.refresh_rounded
                          : Icons.play_arrow_rounded),
                      label: Text(
                        Localizations.localeOf(context).languageCode == 'fr'
                            ? (_videoFailed
                                ? 'Échec du chargement · Réessayer'
                                : 'Appuyer pour lire')
                            : (_videoFailed
                                ? 'Loading failed · Retry'
                                : 'Tap to play'),
                      ),
                    ),
            ),

          Center(
            child: IgnorePointer(child: FadeTransition(
              opacity: _burstOpacity,
              child: ScaleTransition(
                scale: _burstScale,
                child: const Icon(Icons.favorite_rounded,
                    color: Colors.white, size: 96),
              )),
            ),
          ),

          // Paused indicator — only visible while a video is paused, so a
          // single tap always has a clear play-again affordance. A bare
          // icon with a shadow, no backing circle — matches how TikTok's
          // own tap-to-pause feedback reads (mostly just the frozen frame
          // itself, not a heavy overlay).
          if (hasVideo &&
              _videoController != null &&
              _videoController!.value.isInitialized)
            Center(
              child: IgnorePointer(child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _videoController!,
                builder: (context, value, _) => AnimatedOpacity(
                  opacity: value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 72,
                    shadows: [Shadow(blurRadius: 12, color: Colors.black54)],
                  )),
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
          // "@handle" first (TikTok always shows the @-form here, not a
          // display name), then the caption, then a small sound row —
          // there's no separate audio-track metadata to show, so this
          // reads as "original sound" from the post's own author, same as
          // a plain photo/text post on TikTok shows its uploader there.
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
                      radius: 14,
                      backgroundColor: Colors.white24,
                      // The avatar sits inside a 14pt-radius circle
                      // (~28pt across) — decoding at ~96 physical
                      // pixels covers any device pixel ratio without
                      // pulling the full-size source into memory.
                      backgroundImage: post.authorAvatar != null
                          ? MediaCache.imageProvider(
                              ApiService.resolveUrl(post.authorAvatar!),
                              cacheWidth: 96,
                            )
                          : null,
                      child: post.authorAvatar == null
                          ? Text(
                              post.authorName.isNotEmpty
                                  ? post.authorName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '@${post.authorName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          shadows: [
                            Shadow(blurRadius: 6, color: Colors.black54)
                          ],
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
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.music_note_rounded,
                        color: Colors.white,
                        size: 14,
                        shadows: [
                          Shadow(blurRadius: 6, color: Colors.black54)
                        ]),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'original sound - ${post.authorName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          shadows: [
                            Shadow(blurRadius: 6, color: Colors.black54)
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
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
          colors: [AppColors.teal, AppColors.canopyLight, AppColors.ochre],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Faint decorative watermark so a text-only/no-media post still
          // reads as a deliberate "postcard" rather than a blank fill —
          // low-opacity so it never competes with the caption overlay.
          if (!buffering)
            Center(
              child: Icon(
                Icons.travel_explore_rounded,
                size: 120,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
          if (buffering)
            const Center(
              child: SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
