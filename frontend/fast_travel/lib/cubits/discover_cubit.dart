import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../Services/api_service.dart';
import '../models/models.dart';

typedef DestinationLoader = Future<List<Destination>> Function();

class DiscoverState {
  DiscoverState({
    List<Destination> destinations = const [],
    List<String> categories = const [],
    this.query = '',
    this.selectedCategory,
    this.isLoading = true,
    this.hasLoaded = false,
    this.hasError = false,
    this.errorMessage,
  })  : destinations = List.unmodifiable(destinations),
        categories = List.unmodifiable(categories);

  final List<Destination> destinations;
  final List<String> categories;
  final String query;
  final String? selectedCategory;
  final bool isLoading;
  final bool hasLoaded;
  final bool hasError;
  final String? errorMessage;

  List<Destination> get filteredDestinations {
    final normalizedQuery = query.trim().toLowerCase();
    return destinations.where((destination) {
      final categoryMatches = selectedCategory == null ||
          destination.tags.contains(selectedCategory);
      final queryMatches = normalizedQuery.isEmpty ||
          destination.name.toLowerCase().contains(normalizedQuery) ||
          destination.region.toLowerCase().contains(normalizedQuery) ||
          destination.tags
              .any((tag) => tag.toLowerCase().contains(normalizedQuery));
      return categoryMatches && queryMatches;
    }).toList(growable: false);
  }
}

class DiscoverCubit extends Cubit<DiscoverState> {
  DiscoverCubit({DestinationLoader? loadDestinations})
      : _loadDestinations =
            loadDestinations ?? ApiService.instance.getDestinations,
        super(DiscoverState());

  final DestinationLoader _loadDestinations;

  Future<void> load() async {
    final previouslyLoaded = state.hasLoaded;
    emit(DiscoverState(
      destinations: state.destinations,
      categories: state.categories,
      query: state.query,
      selectedCategory: state.selectedCategory,
      isLoading: !previouslyLoaded,
      hasLoaded: previouslyLoaded,
    ));

    try {
      final destinations = await _loadDestinations();
      if (isClosed) return;
      final categories = destinations
          .expand((destination) => destination.tags)
          .toSet()
          .toList()
        ..sort();
      emit(DiscoverState(
        destinations: destinations,
        categories: categories,
        query: state.query,
        selectedCategory: state.selectedCategory,
        isLoading: false,
        hasLoaded: true,
      ));
    } on ApiException catch (error) {
      if (isClosed) return;
      emit(DiscoverState(
        destinations: state.destinations,
        categories: state.categories,
        query: state.query,
        selectedCategory: state.selectedCategory,
        isLoading: false,
        hasLoaded: state.hasLoaded,
        hasError: !state.hasLoaded,
        errorMessage: state.hasLoaded ? null : error.message,
      ));
    } catch (error, stackTrace) {
      debugPrint('Failed to load destinations: $error\n$stackTrace');
      if (isClosed) return;
      emit(DiscoverState(
        destinations: state.destinations,
        categories: state.categories,
        query: state.query,
        selectedCategory: state.selectedCategory,
        isLoading: false,
        hasLoaded: state.hasLoaded,
        hasError: !state.hasLoaded,
      ));
    }
  }

  void updateSearch(String query) {
    emit(DiscoverState(
      destinations: state.destinations,
      categories: state.categories,
      query: query,
      selectedCategory: state.selectedCategory,
      isLoading: state.isLoading,
      hasLoaded: state.hasLoaded,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
    ));
  }

  void selectCategory(String? category) {
    final selectedCategory =
        category == state.selectedCategory ? null : category;
    emit(DiscoverState(
      destinations: state.destinations,
      categories: state.categories,
      query: state.query,
      selectedCategory: selectedCategory,
      isLoading: state.isLoading,
      hasLoaded: state.hasLoaded,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
    ));
  }
}
