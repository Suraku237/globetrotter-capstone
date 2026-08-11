import 'package:flutter/material.dart';
import '../Services/api_service.dart';
import '../theme/app_theme.dart';

/// Full-bleed 2x2 collage of real destination photos behind the
/// login/register forms — replaces the previous single stock photo with
/// actual app content, shown as four images rather than one.
class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key});

  static const _images = [
    '/images/dest_001.jpg', // Olembe Stadium
    '/images/dest_013.jpg', // Mount Cameroon
    '/images/dest_022.jpg', // Lobé Waterfalls
    '/images/dest_029.jpg', // Bafut Palace
  ];

  Widget _photo(String path) => Image.network(
        ApiService.resolveUrl(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const ColoredBox(color: AppColors.canopy),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _photo(_images[0])),
                    Expanded(child: _photo(_images[1])),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _photo(_images[2])),
                    Expanded(child: _photo(_images[3])),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.5)),
        ),
      ],
    );
  }
}
