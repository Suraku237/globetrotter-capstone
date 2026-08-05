import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map_marker_icon.dart';
import '../../widgets/map_platform.dart';

class ItineraryMapScreen extends StatefulWidget {
  final double destLat;
  final double destLng;
  final String destName;

  const ItineraryMapScreen({
    super.key,
    required this.destLat,
    required this.destLng,
    required this.destName,
  });

  @override
  State<ItineraryMapScreen> createState() => _ItineraryMapScreenState();
}

class _ItineraryMapScreenState extends State<ItineraryMapScreen> {
  final MapController _mapController = MapController();
  MapLibreMapController? _mapLibreController;
  Line? _routeLine;
  // maplibre_gl only allows adding annotations (symbols/lines) once the
  // style has actually finished loading — onMapCreated fires too early.
  bool _styleLoaded = false;

  ll.LatLng? _currentLocation;
  bool _loadingLocation = true;
  bool _loadingRoute = false;
  String? _routeError;
  final List<Polyline> _polylines = [];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() => _loadingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services.')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _loadingLocation = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _loadingLocation = false);
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLocation = ll.LatLng(position.latitude, position.longitude);
          _loadingLocation = false;
        });
        if (!use3DMap) {
          _mapController.move(_currentLocation!, 13.0);
        }
        _drawRouteToDestination();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your location.')),
        );
      }
    }
  }

  // Draws the path from the user's current location to this itinerary's
  // destination — same free OSRM routing already used on the Explore Map,
  // just triggered automatically as soon as location is known instead of
  // waiting for a separate button.
  Future<void> _drawRouteToDestination() async {
    final origin = _currentLocation;
    if (origin == null) return;
    // Style not ready yet — _onStyleLoaded() will call this again once it is.
    if (use3DMap && !_styleLoaded) return;

    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });

    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};${widget.destLng},${widget.destLat}'
        '?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Route API error: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded['routes'] == null || decoded['routes'].isEmpty) {
        setState(() {
          _loadingRoute = false;
          _routeError = 'No route found to ${widget.destName}.';
        });
        return;
      }

      final geometry = decoded['routes'][0]['geometry']['coordinates'];
      final routePoints =
          geometry.map<ll.LatLng>((c) => ll.LatLng(c[1], c[0])).toList();

      if (use3DMap && _mapLibreController != null) {
        final controller = _mapLibreController!;
        try {
          if (_routeLine != null) {
            await controller.removeLine(_routeLine!);
            _routeLine = null;
          }
          _routeLine = await controller.addLine(
            LineOptions(
              geometry: routePoints
                  .map((p) => LatLng(p.latitude, p.longitude))
                  .toList(),
              lineColor: '#2C7A73',
              lineWidth: 4.0,
            ),
          );
        } catch (e) {
          if (mounted) {
            setState(() {
              _loadingRoute = false;
              _routeError = "Couldn't draw the path on the map.";
            });
          }
          return;
        }
      } else {
        setState(() {
          _polylines
            ..clear()
            ..add(Polyline(
                points: routePoints, color: AppColors.teal, strokeWidth: 4));
        });
      }

      if (mounted) setState(() => _loadingRoute = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingRoute = false;
          _routeError = "Couldn't load the path. Check your connection.";
        });
      }
    }
  }

  Future<void> _onStyleLoaded() async {
    final controller = _mapLibreController;
    if (controller == null) return;

    setState(() => _styleLoaded = true);

    final bytes = await buildPinMarkerBytes(color: Colors.red);
    await controller.addImage('dest-pin', bytes);
    await controller.addSymbol(
      SymbolOptions(
        geometry: LatLng(widget.destLat, widget.destLng),
        iconImage: 'dest-pin',
        iconSize: 0.5,
      ),
    );

    // Location may have already arrived while the style was still loading —
    // _drawRouteToDestination() bailed out earlier in that case, so retry now.
    if (_currentLocation != null) {
      _drawRouteToDestination();
    }
  }

  Widget _buildMap() {
    final center = _currentLocation ?? ll.LatLng(widget.destLat, widget.destLng);

    if (use3DMap) {
      return MapLibreMap(
        styleString: mapStyleUrl,
        myLocationEnabled: _currentLocation != null,
        onMapCreated: (controller) => _mapLibreController = controller,
        onStyleLoadedCallback: _onStyleLoaded,
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
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'fast_travel',
        ),
        PolylineLayer(polylines: _polylines),
        MarkerLayer(
          markers: [
            Marker(
              point: ll.LatLng(widget.destLat, widget.destLng),
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingLocation) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      appBar: AppBar(
        title: Text('📍 ${widget.destName}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 480 : double.infinity),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            _routeError != null
                                ? Icons.error_outline_rounded
                                : Icons.alt_route_rounded,
                            color: _routeError != null
                                ? AppColors.clay
                                : AppColors.teal,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _loadingRoute
                                  ? 'Finding the path to ${widget.destName}...'
                                  : _routeError ??
                                      'Showing the path to ${widget.destName}.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          if (_loadingRoute)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else if (_routeError != null)
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded),
                              onPressed: _drawRouteToDestination,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
