import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
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
  ll.LatLng? _currentLocation;
  bool _loading = true;

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services.')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    try {
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLocation = ll.LatLng(position.latitude, position.longitude);
          _loading = false;
        });
        // Move the map camera to the user's location (flutter_map/desktop only —
        // the MapLibre branch is built fresh with _currentLocation already as
        // its initial camera target, so it needs no post-load move).
        if (!use3DMap) {
          _mapController.move(_currentLocation!, 14.0);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your location.')),
        );
      }
    }
  }

  Future<void> _onMapLibreCreated(MapLibreMapController controller) async {
    final bytes = await buildPinMarkerBytes(color: Colors.red);
    await controller.addImage('dest-pin', bytes);
    await controller.addSymbol(
      SymbolOptions(
        geometry: LatLng(widget.destLat, widget.destLng),
        iconImage: 'dest-pin',
        iconSize: 0.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('📍 ${widget.destName}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: use3DMap
          ? MapLibreMap(
              styleString: mapStyleUrl,
              myLocationEnabled: true,
              onMapCreated: _onMapLibreCreated,
              initialCameraPosition: CameraPosition(
                target: LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
                zoom: 14.0,
                tilt: 45,
              ),
            )
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation!,
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'fast_travel',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: ll.LatLng(widget.destLat, widget.destLng),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
