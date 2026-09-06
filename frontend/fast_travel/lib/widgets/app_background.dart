import 'package:flutter/material.dart';

/// Full-bleed background used by every screen in the app.
///
/// Shows the Yaoundé cityscape as the app's signature backdrop. Wired
/// globally through [MaterialApp.builder] in main.dart — individual
/// screens don't need to add their own instance, they just need to keep
/// their [Scaffold] background transparent (the theme already does that).
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    // The photo itself, cover-fit so it fills whatever surface it ends
    // up in (phone portrait, tablet landscape, wide web). No off-white
    // veil on top anymore — screens either paint their own opaque cards
    // over this or embrace the full-bleed look intentionally.
    return const Positioned.fill(
      child: Image(
        image: AssetImage('assets/images/hero_yaounde.jpg'),
        fit: BoxFit.cover,
      ),
    );
  }
}
