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

  ll.LatLng? _currentLocation;
  bool _loadingLocation = false;
  bool _loadingDestinations = true;
  bool _isLocationEnabled = false;
  bool _isWaitingForPermission = false;

  List<Destination> _allDestinations = [];
  List<Destination> _searchResults = [];

  final List<Polyline> _polylines = [];

  String? _activeGoDestinationId;

  @override
  void initState() {
    super.initState();
    _loadDestinations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    try {
      final data = await ApiService.instance.getDestinations();
      setState(() {
        _allDestinations = data;
        _searchResults = data;
        _loadingDestinations = false;
      });
    } catch (e) {
      setState(() => _loadingDestinations = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _searchResults = _allDestinations;
      });
    } else {
      setState(() {
        _searchResults = _allDestinations.where((dest) {
          final nameMatch = dest.name.toLowerCase().contains(query);
          final regionMatch = dest.region.toLowerCase().contains(query);
          final tagsMatch =
              dest.tags.any((tag) => tag.toLowerCase().contains(query));
          return nameMatch || regionMatch || tagsMatch;
        }).toList();
      });
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
            .map<ll.LatLng>((c) => ll.LatLng(
                (c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();

        if (use3DMap && _mapLibreController != null) {
          final controller = _mapLibreController!;
          if (_routeLine != null) {
            await controller.removeLine(_routeLine!);
          }
          _routeLine = await controller.addLine(
            LineOptions(
              geometry:
                  routePoints.map((p) => LatLng(p.latitude, p.longitude)).toList(),
              lineColor: '#2196F3',
              lineWidth: 4.0,
            ),
          );
        } else {
          setState(() {
            _polylines
              ..clear()
              ..add(Polyline(points: routePoints, color: Colors.blue, strokeWidth: 4));
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

    return Scaffold(
      backgroundColor: AppColors.sand,
      // No AppBar here — AdaptiveShell already renders the "Explore Map"
      // title; a second one here would show it twice.
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search destinations...',
                prefixIcon: const Icon(Icons.search_rounded),
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
            if (!_isLocationEnabled && !_loadingLocation)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _isWaitingForPermission ? null : _requestUserLocation,
                  icon: _isWaitingForPermission
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
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
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              flex: 5,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.clay.withOpacity(0.2)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildMap(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 1,
              child: _searchResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48, color: AppColors.clay),
                          const SizedBox(height: 8),
                          Text(
                            'No destinations found',
                            style:
                                TextStyle(color: AppColors.clay, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _searchResults.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final dest = _searchResults[index];
                        final bool isGoActive =
                            _activeGoDestinationId == dest.id;

                        final bool isButtonEnabled = _currentLocation != null &&
                            _currentLocation!.latitude != 0.0 &&
                            _currentLocation!.longitude != 0.0 &&
                            _currentLocation!.latitude > 1.0 &&
                            _currentLocation!.longitude > 1.0;

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: Image.network(
                                      ApiService.resolveUrl(dest.imageUrl ?? ''),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                        color: AppColors.canopy,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.image,
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dest.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        dest.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.inkSoft),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: 36,
                                  child: ElevatedButton.icon(
                                    onPressed: isButtonEnabled
                                        ? () {
                                            setState(() {
                                              _activeGoDestinationId = dest.id;
                                            });
                                            _drawRoute(dest.lat, dest.lng);
                                          }
                                        : null,
                                    icon: const Icon(Icons.directions_car,
                                        size: 16),
                                    label: const Text('show path',
                                        style: TextStyle(fontSize: 12)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isGoActive
                                          ? Colors.blue
                                          : Colors.green,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
