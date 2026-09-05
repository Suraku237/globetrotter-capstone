import 'package:flutter/material.dart';

/// Full-bleed background used by every screen in the app.
///
/// Shows the Yaoundé cityscape as the app's signature backdrop with a
/// slightly translucent white veil on top so text, cards and forms stay
/// legible. Wired globally through [MaterialApp.builder] in main.dart —
/// individual screens don't need to add their own instance, they just
/// need to keep their [Scaffold] background transparent (the theme
/// already does that).
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        // The photo itself — cover-fit so it fills whatever surface it
        // ends up in (phone portrait, tablet landscape, wide web).
        Positioned.fill(
          child: Image(
            image: AssetImage('assets/images/hero_yaounde.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        // Warm off-white veil that keeps forms and long text legible on
        // top of the photo. Alpha is deliberately high enough to protect
        // small body text, but not so high that the image disappears.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xE6FAF9F6),
                  Color(0xCCFAF9F6),
                  Color(0xE0FAF9F6),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
