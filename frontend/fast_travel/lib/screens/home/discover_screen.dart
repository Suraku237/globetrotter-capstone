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
    // Pushed as a full page (previously a modal dialog) so the map picker,
    // photo picker, description field, and error surface all get room to
    // breathe on phones. The screen still returns a bool over Navigator.pop
    // so the "submitted" branch below is unchanged.
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SuggestDestinationScreen(isAdmin: widget.isAdmin),
      ),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Transparent so the global AppBackground photo (see main.dart)
    // shows through this screen — the hero card and bottom Suggest
    // pill are gone because the same image is now behind everything.
    return Scaffold(
      backgroundColor: Colors.transparent,
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
              Expanded(child: _buildBody(l10n)),
              const SizedBox(height: 10),
              // Only the Ask AI shortcut lives in the bottom row now —
              // the Suggest a destination action moved to a small FAB
              // on the right so it stays reachable without dominating
              // the layout.
              Row(
                children: [
                  _AskAiButton(onTap: _openAssistant),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'suggest_destination_fab',
        onPressed: _openSuggestDestination,
        backgroundColor: AppColors.ochre,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: Text(
          widget.isAdmin ? l10n.addDestination : l10n.suggestDestination,
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
