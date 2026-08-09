import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../Services/api_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/destination_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/region_ribbon.dart';
import '../discover/suggest_destination_screen.dart';
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
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedRegion;

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
      setState(() {
        _allDestinations = data;
        _filteredDestinations = data;
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
        final regionMatch =
            _selectedRegion == null || dest.region == _selectedRegion;
        final nameMatch = dest.name.toLowerCase().contains(query);
        final searchRegionMatch = dest.region.toLowerCase().contains(query);
        final tagsMatch =
            dest.tags.any((tag) => tag.toLowerCase().contains(query));
        return regionMatch && (nameMatch || searchRegionMatch || tagsMatch);
      }).toList();
    });
  }

  void _onRegionSelected(String? region) {
    setState(() {
      _selectedRegion = (region == _selectedRegion) ? null : region;
    });
    _onSearchOrFilterChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.sand,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.searchHint,
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: AppColors.clay),
                  filled: true,
                  fillColor: AppColors.sandDim,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              RegionRibbon(
                selected: _selectedRegion,
                onSelect: _onRegionSelected,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? EmptyState(
                            icon: Icons.wifi_off_rounded,
                            title: l10n.cantReachServer,
                            message: _error!,
                            onRetry: _loadDestinations,
                          )
                        : _filteredDestinations.isEmpty
                            ? EmptyState(
                                icon: Icons.search_off_rounded,
                                title: l10n.noResultsFound,
                                message: l10n.noResultsMessage,
                              )
                            : GridView.builder(
                                padding:
                                    const EdgeInsets.only(bottom: 20, top: 4),
                                // Target a fixed card width and let the
                                // column count adapt to it, instead of a
                                // fixed column count that squeezes cards
                                // (and their images) smaller as the screen
                                // narrows.
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 200,
                                  childAspectRatio: 0.65,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
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
                                              DestinationDetailScreen(
                                                  destination: dest),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'suggest_destination_fab',
        onPressed: () async {
          final submitted = await showDialog<bool>(
            context: context,
            builder: (_) => SuggestDestinationScreen(isAdmin: widget.isAdmin),
          );
          if (submitted == true && context.mounted) {
            _loadDestinations();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.isAdmin
                    ? l10n.destinationAdded
                    : l10n.submittedForReview),
              ),
            );
          }
        },
        icon: const Icon(Icons.add_location_alt_rounded),
        label: Text(widget.isAdmin ? l10n.addDestination : l10n.suggestDestination),
      ),
    );
  }
}
