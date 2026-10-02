import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../Services/api_service.dart';
import '../../Services/live_refresh.dart';
import '../../cubits/discover_cubit.dart';
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
  late final DiscoverCubit _cubit;
  late final LiveRefresh _refresh;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cubit = DiscoverCubit();
    _refresh = LiveRefresh(
      changes: ApiService.instance.changes,
      topics: {'destinations'},
      onRefresh: _cubit.load,
    );
    _loadDestinations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _refresh.dispose();
    _searchController.dispose();
    unawaited(_cubit.close());
    super.dispose();
  }

  Future<void> _loadDestinations() => _refresh.refresh();

  void _onSearchChanged() {
    _cubit.updateSearch(_searchController.text);
  }

  Future<void> _openSuggestDestination() async {
    final l10n = AppLocalizations.of(context)!;
    // Compact brown modal (redesigned from the previous full-page
    // Scaffold) — showDialog gives it the barrier-dim and the standard
    // "tap outside to dismiss" behavior. The dialog still returns a
    // bool over Navigator.pop, so the submitted branch below is
    // unchanged.
    final submitted = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.canopy.withValues(alpha: 0.72),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<DiscoverCubit, DiscoverState>(
        builder: (context, state) => Scaffold(
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
                    categories: state.categories,
                    selected: state.selectedCategory,
                    onSelect: _cubit.selectCategory,
                  ),
                  const SizedBox(height: 14),
                  Expanded(child: _buildBody(state, l10n)),
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
        ),
      ),
    );
  }

  Widget _buildBody(DiscoverState state, AppLocalizations l10n) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: l10n.cantReachServer,
        message: state.errorMessage ?? l10n.couldNotReachServerShort,
        onRetry: _loadDestinations,
      );
    }
    if (state.filteredDestinations.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: l10n.noResultsFound,
        message: l10n.noResultsMessage,
      );
    }
    final destinations = state.filteredDestinations;
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
      itemCount: destinations.length,
      itemBuilder: (context, index) {
        final dest = destinations[index];
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
