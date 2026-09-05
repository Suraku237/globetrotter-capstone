import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../Services/api_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/category_ribbon.dart';
import '../../widgets/destination_card.dart';
import '../../widgets/empty_state.dart';
import '../assistant/assistant_screen.dart';
import '../discover/suggest_destination_screen.dart';
import '../itineraries/itineraries_screen.dart';
import 'destination_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  final bool isAdmin;
  const DiscoverScreen({super.key, this.isAdmin = false});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Destination> _allDestinations = [];
  List<Destination> _filteredDestinations = [];
  List<String> _categories = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadDestinations();
    _searchController.addListener(_onSearchOrFilterChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.instance.getDestinations();
      // Categories always match whatever tags actually exist on the
      // loaded destinations, sorted, instead of a hardcoded list that
      // could drift out of sync with real data.
      final categories = data.expand((d) => d.tags).toSet().toList()..sort();
      setState(() {
        _allDestinations = data;
        _filteredDestinations = data;
        _categories = categories;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() =>
          _error = AppLocalizations.of(context)!.couldNotReachServerShort);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchOrFilterChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredDestinations = _allDestinations.where((dest) {
        final categoryMatch =
            _selectedCategory == null || dest.tags.contains(_selectedCategory);
        final nameMatch = dest.name.toLowerCase().contains(query);
        final searchRegionMatch = dest.region.toLowerCase().contains(query);
        final tagsMatch =
            dest.tags.any((tag) => tag.toLowerCase().contains(query));
        return categoryMatch && (nameMatch || searchRegionMatch || tagsMatch);
      }).toList();
    });
  }

  void _onCategorySelected(String? category) {
    setState(() {
      _selectedCategory = (category == _selectedCategory) ? null : category;
    });
    _onSearchOrFilterChanged();
  }

  Future<void> _openSuggestDestination() async {
    final l10n = AppLocalizations.of(context)!;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) => SuggestDestinationScreen(isAdmin: widget.isAdmin),
    );
    if (submitted == true && mounted) {
      _loadDestinations();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isAdmin
              ? l10n.destinationAdded
              : l10n.submittedForReview),
        ),
      );
    }
  }

  void _openAssistant() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AssistantScreen()),
    );
  }

  void _openTripPlanner() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ItinerariesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SearchBar(
                controller: _searchController,
                hint: l10n.searchHint,
              ),
              const SizedBox(height: 14),
              CategoryRibbon(
                categories: _categories,
                selected: _selectedCategory,
                onSelect: _onCategorySelected,
              ),
              const SizedBox(height: 14),
              // Hero card featuring the Yaoundé cityscape — matches the
              // reference mockup: photo fills the card, location label
              // sits in the bottom-left, and a "Suggest a destination"
              // pill sits in the bottom-right so the action stays with
              // the destination it applies to.
              _HeroCard(
                onSuggest: _openSuggestDestination,
                suggestLabel: widget.isAdmin
                    ? l10n.addDestination
                    : l10n.suggestDestination,
              ),
              const SizedBox(height: 14),
              Expanded(child: _buildBody(l10n)),
              const SizedBox(height: 10),
              // Bottom action row: Ask AI shortcut on the left, the
              // main "Plan your trip" CTA in the middle, and a compact
              // "Suggest a destination" pill on the right — same set
              // and same left-to-right order as the reference mockup.
              _BottomActions(
                isAdmin: widget.isAdmin,
                onAskAi: _openAssistant,
                onPlanTrip: _openTripPlanner,
                onSuggest: _openSuggestDestination,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: l10n.cantReachServer,
        message: _error!,
        onRetry: _loadDestinations,
      );
    }
    if (_filteredDestinations.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: l10n.noResultsFound,
        message: l10n.noResultsMessage,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      // Target a fixed card width and let the column count adapt to
      // it, instead of a fixed column count that squeezes cards (and
      // their images) smaller as the screen narrows.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        childAspectRatio: 0.72,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _filteredDestinations.length,
      itemBuilder: (context, index) {
        final dest = _filteredDestinations[index];
        return DestinationCard(
          destination: dest,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    DestinationDetailScreen(destination: dest),
              ),
            );
          },
          onAskAi: _openAssistant,
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _SearchBar({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0.5,
      borderRadius: BorderRadius.circular(30),
      color: Colors.white,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon:
              const Icon(Icons.search_rounded, color: AppColors.clay),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(
              color: AppColors.inkSoft.withValues(alpha: 0.2),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(
              color: AppColors.inkSoft.withValues(alpha: 0.2),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide:
                const BorderSide(color: AppColors.ochre, width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final VoidCallback onSuggest;
  final String suggestLabel;

  const _HeroCard({required this.onSuggest, required this.suggestLabel});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Image(
              image: AssetImage('assets/images/hero_yaounde.jpg'),
              fit: BoxFit.cover,
            ),
            // Bottom-to-top gradient so the "Yaoundé, Cameroon" label
            // stays legible over the busiest part of the photo without
            // covering the sky above.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x00000000),
                    Color(0x66000000),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            const Positioned(
              left: 20,
              bottom: 18,
              child: Text(
                'Yaoundé, Cameroon',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 4,
                      color: Color(0x99000000),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 14,
              child: _PillButton(
                icon: Icons.add_location_alt_rounded,
                label: suggestLabel,
                onPressed: onSuggest,
                background: AppColors.ochre,
                foreground: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final bool isAdmin;
  final VoidCallback onAskAi;
  final VoidCallback onPlanTrip;
  final VoidCallback onSuggest;

  const _BottomActions({
    required this.isAdmin,
    required this.onAskAi,
    required this.onPlanTrip,
    required this.onSuggest,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        _AskAiButton(onTap: onAskAi),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ochre,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            onPressed: onPlanTrip,
            icon: const Icon(Icons.route_rounded),
            label: const Text('Plan your trip'),
          ),
        ),
        const SizedBox(width: 12),
        _PillButton(
          icon: Icons.add_location_alt_rounded,
          label: isAdmin ? l10n.addDestination : l10n.suggestDestination,
          onPressed: onSuggest,
          background: AppColors.sand,
          foreground: AppColors.ink,
        ),
      ],
    );
  }
}

class _AskAiButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AskAiButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ask AI',
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.ochre, Color(0xFFFF9A76)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ochre.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            'AI',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color background;
  final Color foreground;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(24),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPressed,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
