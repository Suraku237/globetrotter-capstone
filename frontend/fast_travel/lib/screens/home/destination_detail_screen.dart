import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../Services/api_service.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/star_rating.dart';
import '../assistant/assistant_screen.dart';
import '../itineraries/itineraries_screen.dart';
import '../itineraries/itinerary_map_screen.dart';

class DestinationDetailScreen extends StatefulWidget {
  final Destination destination;

  const DestinationDetailScreen({super.key, required this.destination});

  @override
  State<DestinationDetailScreen> createState() =>
      _DestinationDetailScreenState();
}

class _DestinationDetailScreenState extends State<DestinationDetailScreen> {
  final FlutterTts _tts = FlutterTts();

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  String get _description => widget.destination.description.isNotEmpty
      ? widget.destination.description
      : 'No description available for this location.';

  Future<void> _speakDescription() async {
    await _tts.speak('${widget.destination.name}. $_description');
  }

  void _showOnMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItineraryMapScreen(
          destLat: widget.destination.lat,
          destLng: widget.destination.lng,
          destName: widget.destination.name,
        ),
      ),
    );
  }

  void _planTrip() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('Plan a Trip')),
          body: SafeArea(
            child: ItinerariesScreen(presetDestination: widget.destination),
          ),
        ),
      ),
    );
  }

  void _askAssistant() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AssistantScreen(
          initialQuestion:
              'Tell me more about ${widget.destination.name} in ${widget.destination.region}, Cameroon.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.destination;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero image with a floating back button and a name/rating/
            // location card overlapping its bottom edge.
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 340,
                    child: Image.network(
                      ApiService.resolveUrl(destination.imageUrl ?? ''),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppColors.canopy,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_not_supported,
                            color: AppColors.ochre, size: 48),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: SafeArea(
                    bottom: false,
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.4),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: -64,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.canopy.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                destination.name,
                                style: textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _HeroIconButton(
                              icon: Icons.volume_up_rounded,
                              tooltip: 'Read description aloud',
                              onTap: _speakDescription,
                            ),
                            _HeroIconButton(
                              icon: Icons.directions_rounded,
                              tooltip: 'Show on map',
                              onTap: _showOnMap,
                            ),
                            _HeroIconButton(
                              icon: Icons.playlist_add_rounded,
                              tooltip: 'Plan a trip here',
                              onTap: _planTrip,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        StarRating(
                          rating: destination.rating,
                          size: 16,
                          color: AppColors.ochre,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.location_on_rounded,
                                size: 16,
                                color: AppColors.sand.withValues(alpha: 0.75)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                destination.region,
                                style: TextStyle(
                                    color:
                                        AppColors.sand.withValues(alpha: 0.75),
                                    fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 84),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (destination.tags.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: destination.tags
                          .map((tag) => Chip(
                                label: Text(tag),
                                backgroundColor: AppColors.sandDim,
                                side: BorderSide.none,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 0),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'About',
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _description,
                    style: textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      color: AppColors.ink.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ActionRow(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Ask the assistant to explain',
                    onTap: _askAssistant,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Good to know',
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  _ActionRow(
                    icon: Icons.map_outlined,
                    title: 'View on map',
                    subtitle: 'See ${destination.name} and get directions',
                    onTap: _showOnMap,
                  ),
                  const SizedBox(height: 40),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _planTrip,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.ochre,
                            foregroundColor: AppColors.ink,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('Plan Trip'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Booking travel to ${destination.name}...')),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.ink,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            side: const BorderSide(
                                color: AppColors.ink, width: 1.5),
                            elevation: 0,
                          ),
                          child: const Text('Travel Now'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeroIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white, size: 20),
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: const EdgeInsets.all(6),
    );
  }
}

/// A tappable "good to know"-style row: icon, title (+ optional subtitle),
/// chevron — used for both the assistant shortcut and the map link.
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.sandDim,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.ochre),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.inkSoft)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
