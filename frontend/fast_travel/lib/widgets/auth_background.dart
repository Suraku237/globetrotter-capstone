import 'dart:async';

import 'package:flutter/material.dart';
import '../Services/api_service.dart';
import '../theme/app_theme.dart';

/// Full-bleed background photo behind every screen (see MaterialApp's
/// `builder` in main.dart) — a single cover-fit image that always fills
/// whatever size the window/screen currently is (BoxFit.cover inside
/// Positioned.fill reflows on any resize, same as any other image), and
/// crossfades to the next photo in the pool every 5 seconds.
class AuthBackground extends StatefulWidget {
  const AuthBackground({super.key});

  @override
  State<AuthBackground> createState() => _AuthBackgroundState();
}

class _AuthBackgroundState extends State<AuthBackground> {
  static const _images = [
    '/images/dest_001.jpg',
    '/images/dest_013.jpg',
    '/images/dest_022.jpg',
    '/images/dest_029.jpg',
    '/images/dest_009.jpg',
    '/images/dest_017.jpg',
    '/images/dest_025.jpg',
    '/images/dest_033.jpg',
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Precache the next image ahead of time so each 5s crossfade shows an
    // already-loaded photo instead of popping in mid-fade on a slow
    // connection.
    WidgetsBinding.instance.addPostFrameCallback((_) => _precache(_next()));
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _index = _next());
      _precache(_next());
    });
  }

  int _next() => (_index + 1) % _images.length;

  void _precache(int index) {
    if (!mounted) return;
    precacheImage(NetworkImage(ApiService.resolveUrl(_images[index])), context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            child: Image.network(
              ApiService.resolveUrl(_images[_index]),
              key: ValueKey(_index),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: AppColors.canopy),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.5)),
        ),
      ],
    );
  }
}
