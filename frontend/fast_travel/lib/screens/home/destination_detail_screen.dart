import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

class DestinationDetailScreen extends StatelessWidget {
  final Destination destination;

  const DestinationDetailScreen({super.key, required this.destination});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(destination.name,
            style: Theme.of(context).textTheme.titleLarge),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. ENLARGED IMAGE
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 500,
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

              const SizedBox(height: 24),

              // 2. DESTINATION NAME & REGION
              Text(
                destination.name,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                destination.region.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.clay,
                      letterSpacing: 1.2,
                    ),
              ),

              const SizedBox(height: 20),

              // 3. "ABOUT" SECTION
              Text(
                "About",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                destination.description.isNotEmpty
                    ? destination.description
                    : "No description available for this location.",
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      color: AppColors.ink.withValues(alpha: 0.8),
                    ),
              ),

              const SizedBox(height: 24),

              // 4. TAGS SECTION
              Text(
                "Highlights",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
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

              const SizedBox(height: 40),

              // 5. TWO BUTTONS: PLAN TRIP & TRAVEL NOW
              Row(
                children: [
                  // Button 1: Plan Trip
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("Opening trip planner...")),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ochre,
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text("Plan Trip"),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Button 2: Travel Now
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  "Booking travel to ${destination.name}...")),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side:
                            const BorderSide(color: AppColors.ink, width: 1.5),
                        elevation: 0,
                      ),
                      child: const Text("Travel Now"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
