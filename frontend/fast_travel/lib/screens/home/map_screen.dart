import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../Services/api_service.dart';
import '../../widgets/map_platform.dart';

// A search result on the map screen — either one of the app's own curated
// destinations, or a real-world place found via OpenStreetMap's Nominatim
// search (isExternal: true) that isn't in destinations.json at all. Both
// render the same way in the results list and both can have a route drawn
// to them.
class _MapSearchResult {
  final String id;
  final String name;
  final String description;
  final double lat;
  final double lng;
  final String? imageUrl;
  final bool isExternal;

  _MapSearchResult({
    required this.id,
    required this.name,
    required this.description,
    required this.lat,
    required this.lng,
    this.imageUrl,
    this.isExternal = false,
  });

  factory _MapSearchResult.fromDestination(Destination d) => _MapSearchResult(
        id: d.id,
        name: d.name,
        description: d.description,
        lat: d.lat,
        lng: d.lng,
        imageUrl: d.imageUrl,
      );
}

class ExploreMapScreen extends StatefulWidget {
  const ExploreMapScreen({super.key});

  @override
  State<ExploreMapScreen> createState() => _ExploreMapScreenState();
}

class _ExploreMapScreenState extends State<ExploreMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  MapLibreMapController? _mapLibreController;
  Line? _routeLine;
  Circle? _locationCircle;
  Circle? _searchResultCircle;

  // Wherever the search bar last sent the map — replaces the old
  // destinations list/buttons panel: submitting a search jumps the map
  // straight to the best match and drops a single marker there instead of
  // showing a separate list of "show path" buttons.
  ll.LatLng? _searchMarkerLocation;

  ll.LatLng? _currentLocation;
  bool _loadingLocation = false;
  bool _loadingDestinations = true;
  bool _isLocationEnabled = false;
  bool _isWaitingForPermission = false;

  List<Destination> _allDestinations = [];
  List<_MapSearchResult> _searchResults = [];
  bool _searchingExternal = false;
  Timer? _searchDebounce;

  final List<Polyline> _polylines = [];

  @override
  void initState() {
    super.initState();
    _loadDestinations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    try {
      final data = await ApiService.instance.getDestinations();
      setState(() {
        _allDestinations = data;
        _searchResults = data.map(_MapSearchResult.fromDestination).toList();
        _loadingDestinations = false;
      });
    } catch (e) {
      setState(() => _loadingDestinations = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    final lowerQuery = query.toLowerCase();
    _searchDebounce?.cancel();

    if (lowerQuery.isEmpty) {
      setState(() {
        _searchResults =
            _allDestinations.map(_MapSearchResult.fromDestination).toList();
        _searchingExternal = false;
      });
      return;
    }

    final localMatches = _allDestinations
        .where((dest) {
          final nameMatch = dest.name.toLowerCase().contains(lowerQuery);
          final regionMatch = dest.region.toLowerCase().contains(lowerQuery);
          final tagsMatch =
              dest.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
          return nameMatch || regionMatch || tagsMatch;
        })
        .map(_MapSearchResult.fromDestination)
        .toList();

    setState(() {
      _searchResults = localMatches;
      _searchingExternal = true;
    });

    // Debounced — Nominatim's public instance asks for roughly one request
    // per second at most, and there's no point firing one on every
    // keystroke while the user is still typing.
    _searchDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _searchExternalPlaces(query, localMatches),
    );
  }

  // Anything typed here that isn't one of the app's curated destinations
  // still gets looked up as a real place via OpenStreetMap's free
  // Nominatim geocoder (same "no paid API key" approach already used for
  // routing via OSRM below) — restricted to Cameroon only.
  Future<void> _searchExternalPlaces(
      String query, List<_MapSearchResult> localMatches) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '6',
        'countrycodes': 'cm', // hard filter — Cameroon results only
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'FastTravelApp/1.0 (kwetejunior9@gmail.com)',
        },
      );
      if (!mounted || response.statusCode != 200) return;
      // The query may have changed (or been cleared) while this request
      // was in flight — a stale response arriving late shouldn't clobber
      // whatever's actually being searched for now.
      if (_searchController.text.trim() != query) return;

      final List<dynamic> raw = jsonDecode(response.body);
      final localNames = localMatches.map((r) => r.name.toLowerCase()).toSet();
      final external = raw
          .map((r) => _MapSearchResult(
                id: 'osm_${r['place_id']}',
                name: (r['display_name'] as String).split(',').first,
                description: r['display_name'] as String,
                lat: double.parse(r['lat'] as String),
                lng: double.parse(r['lon'] as String),
                isExternal: true,
              ))
          .where((e) => !localNames.contains(e.name.toLowerCase()))
          .toList();

      setState(() {
        _searchResults = [...localMatches, ...external];
        _searchingExternal = false;
      });
    } catch (_) {
      // Silent — the local matches already found are still shown either
      // way; this is just the "also search everywhere else" layer on top.
      if (mounted) setState(() => _searchingExternal = false);
    }
  }

  void _onSearchSubmitted(String value) {
    if (_searchResults.isEmpty) return;
    _goToSearchResult(_searchResults.first);
  }

  // Replaces what used to be a tap on one of the destination-list "show
  // path" buttons: jumps the map to the result, drops a marker there, and
  // draws the route immediately if location's already on — otherwise
  // offers to turn it on instead of failing silently.
  void _goToSearchResult(_MapSearchResult result) {
    final target = ll.LatLng(result.lat, result.lng);
    setState(() => _searchMarkerLocation = target);

    if (use3DMap) {
      _mapLibreController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(result.lat, result.lng), 15.0),
      );
      _syncSearchMarker();
    } else {
      _mapController.move(target, 15.0);
    }

    final isLocationReady = _currentLocation != null &&
        _currentLocation!.latitude != 0.0 &&
        _currentLocation!.longitude != 0.0 &&
        _currentLocation!.latitude > 1.0 &&
        _currentLocation!.longitude > 1.0;

    if (!mounted) return;
    if (isLocationReady) {
      _drawRoute(result.lat, result.lng);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Showing route to ${result.name}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Showing ${result.name}'),
          action: SnackBarAction(
              label: 'Directions', onPressed: _requestUserLocation),
        ),
      );
    }
  }

  // Same idea as _syncLocationMarker below, just for wherever the search
  // last jumped to instead of the user's own GPS position.
  Future<void> _syncSearchMarker() async {
    final controller = _mapLibreController;
    final loc = _searchMarkerLocation;
    if (controller == null || loc == null) return;

    final options = CircleOptions(
      geometry: LatLng(loc.latitude, loc.longitude),
      circleRadius: 9.0,
      circleColor: '#E2A33D',
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 3.0,
    );

    if (_searchResultCircle != null) {
      await controller.updateCircle(_searchResultCircle!, options);
    } else {
      _searchResultCircle = await controller.addCircle(options);
    }
  }

  Future<void> _requestUserLocation() async {
    setState(() {
      _isWaitingForPermission = true;
      _loadingLocation = true;
    });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorDialog('Location services are disabled. Please enable GPS.');
      setState(() {
        _isWaitingForPermission = false;
        _loadingLocation = false;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorDialog('Location permission denied.');
        setState(() {
          _isWaitingForPermission = false;
          _loadingLocation = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showErrorDialog(
          'Location permissions permanently denied. Please enable in browser settings.');
      setState(() {
        _isWaitingForPermission = false;
        _loadingLocation = false;
      });
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );

      if (mounted) {
        setState(() {
          _currentLocation = ll.LatLng(position.latitude, position.longitude);
          _isLocationEnabled = true;
          _loadingLocation = false;
          _isWaitingForPermission = false;
        });

        if (use3DMap) {
          await _mapLibreController?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
              16.0,
            ),
          );
          await _syncLocationMarker();
        } else {
          _mapController.move(_currentLocation!, 16.0);
        }
      }
    } catch (e) {
      setState(() {
        _currentLocation = const ll.LatLng(3.8480, 11.5021);
        _isLocationEnabled = false;
        _loadingLocation = false;
        _isWaitingForPermission = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Precise location unavailable. Showing Yaoundé.')),
      );
    }
  }

  // Free OSRM public routing API — no key needed. Rendering the resulting
  // line differs by map engine (flutter_map's Polyline widget vs MapLibre's
  // addLine), but the fetch/parse logic is identical either way.
  Future<void> _drawRoute(double destLat, double destLng) async {
    if (_currentLocation == null) return;
    if (_currentLocation!.latitude == 0.0 &&
        _currentLocation!.longitude == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Waiting for GPS location... Try again in 5 seconds.')),
      );
      return;
    }

    final String url =
        'https://router.project-osrm.org/route/v1/driving/${_currentLocation!.longitude},${_currentLocation!.latitude};${destLng},${destLat}?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded['routes'] == null || decoded['routes'].isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No route found. Try another destination.')),
          );
          return;
        }

        final List<dynamic> geometry =
            decoded['routes'][0]['geometry']['coordinates'];
        final List<ll.LatLng> routePoints = geometry
            .map<ll.LatLng>((c) =>
                ll.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();

        if (use3DMap && _mapLibreController != null) {
          final controller = _mapLibreController!;
          if (_routeLine != null) {
            await controller.removeLine(_routeLine!);
          }
          _routeLine = await controller.addLine(
            LineOptions(
              geometry: routePoints
                  .map((p) => LatLng(p.latitude, p.longitude))
                  .toList(),
              lineColor: '#2196F3',
              lineWidth: 4.0,
            ),
          );
        } else {
          setState(() {
            _polylines
              ..clear()
              ..add(Polyline(
                  points: routePoints, color: Colors.blue, strokeWidth: 4));
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Route API Error: ${response.statusCode}')),
        );
      }
    } catch (e) {
      debugPrint('Route fetch error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect to route server: $e')),
      );
    }
  }

  // MapLibre's built-in `myLocationEnabled` puck is unreliable on Flutter
  // Web, so the 3D map gets its own explicit ping — flutter_map's 2D branch
  // already draws one via MarkerLayer/_buildCustomLocationMarker.
  Future<void> _syncLocationMarker() async {
    final controller = _mapLibreController;
    if (controller == null || _currentLocation == null) return;

    final options = CircleOptions(
      geometry: LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
      circleRadius: 9.0,
      circleColor: '#2196F3',
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 3.0,
    );

    if (_locationCircle != null) {
      await controller.updateCircle(_locationCircle!, options);
    } else {
      _locationCircle = await controller.addCircle(options);
    }
  }

  void _showErrorDialog(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildCustomLocationMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 5,
              ),
            ],
          ),
        ),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.blue, width: 3),
          ),
        ),
        Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2196F3), Color(0xFF0D47A1)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue,
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    final center = _currentLocation ?? const ll.LatLng(3.8480, 11.5021);

    if (use3DMap) {
      return MapLibreMap(
        styleString: mapStyleUrl,
        myLocationEnabled: _isLocationEnabled,
        onMapCreated: (controller) {
          _mapLibreController = controller;
          _syncLocationMarker();
        },
        initialCameraPosition: CameraPosition(
          target: LatLng(center.latitude, center.longitude),
          zoom: 13.0,
          tilt: 45,
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'fast_travel',
          subdomains: const ['a', 'b', 'c'],
        ),
        PolylineLayer(polylines: _polylines),
        if (_currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _currentLocation!,
                width: 40,
                height: 40,
                child: _buildCustomLocationMarker(),
              ),
            ],
          ),
        if (_searchMarkerLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _searchMarkerLocation!,
                width: 44,
                height: 44,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on,
                    color: AppColors.ochre, size: 44),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDestinations) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Full-bleed map — no side panel or destinations list splitting the
    // screen with it anymore. Search now jumps the map straight to a
    // result (see _goToSearchResult) and drops a single marker there
    // instead of listing every match as its own "show path" button.
    return Scaffold(
      backgroundColor: Colors.transparent,
      // No AppBar here — AdaptiveShell already renders the "Explore Map"
      // title; a second one here would show it twice.
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),
          Positioned(
            top: 0,
            left: 16,
            right: 16,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: _onSearchSubmitted,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search any destination or place...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        // Small spinner while the "also search everywhere
                        // else" OpenStreetMap lookup is still in flight.
                        suffixIcon: _searchingExternal
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.sand,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                  if (!_isLocationEnabled && !_loadingLocation) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isWaitingForPermission
                            ? null
                            : _requestUserLocation,
                        icon: _isWaitingForPermission
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location),
                        label: Text(_isWaitingForPermission
                            ? 'Fetching Location...'
                            : '📍 Enable My Location'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.ochre,
                          foregroundColor: AppColors.ink,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
