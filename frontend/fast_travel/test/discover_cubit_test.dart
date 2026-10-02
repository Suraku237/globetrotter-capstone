import 'package:fast_travel/Services/api_service.dart';
import 'package:fast_travel/cubits/discover_cubit.dart';
import 'package:fast_travel/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Destination _destination({
  required String id,
  required String name,
  required String region,
  required List<String> tags,
}) =>
    Destination(
      id: id,
      name: name,
      region: region,
      tags: tags,
      description: '',
      lat: 0,
      lng: 0,
    );

void main() {
  final destinations = [
    _destination(
      id: 'kribi',
      name: 'Kribi Beach',
      region: 'South',
      tags: ['Beach', 'Nature'],
    ),
    _destination(
      id: 'waza',
      name: 'Waza National Park',
      region: 'Far North',
      tags: ['Nature', 'Wildlife'],
    ),
  ];

  test('loads destinations and derives sorted categories', () async {
    final cubit = DiscoverCubit(loadDestinations: () async => destinations);
    await cubit.load();

    expect(cubit.state.hasLoaded, isTrue);
    expect(cubit.state.destinations, hasLength(2));
    expect(cubit.state.categories, ['Beach', 'Nature', 'Wildlife']);
    expect(cubit.state.isLoading, isFalse);
    await cubit.close();
  });

  test('filters by query and selected category', () async {
    final cubit = DiscoverCubit(loadDestinations: () async => destinations);
    await cubit.load();

    cubit.updateSearch('far north');
    expect(cubit.state.filteredDestinations.map((item) => item.id), ['waza']);

    cubit.updateSearch('');
    cubit.selectCategory('Beach');
    expect(cubit.state.filteredDestinations.map((item) => item.id), ['kribi']);

    cubit.selectCategory('Beach');
    expect(cubit.state.filteredDestinations, hasLength(2));
    await cubit.close();
  });

  test('exposes API failure for the retry state', () async {
    final cubit = DiscoverCubit(
      loadDestinations: () async => throw ApiException('Service unavailable'),
    );
    await cubit.load();

    expect(cubit.state.hasError, isTrue);
    expect(cubit.state.errorMessage, 'Service unavailable');
    expect(cubit.state.isLoading, isFalse);
    await cubit.close();
  });
}
