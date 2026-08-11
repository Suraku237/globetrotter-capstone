import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../widgets/map_marker_icon.dart';
import '../../widgets/map_platform.dart';

const _kInitialLat = 3.8480;
const _kInitialLng = 11.5021;

class SelectDestinationMap extends StatefulWidget {
  final Function(ll.LatLng) onLocationSelected;

  const SelectDestinationMap({super.key, required this.onLocationSelected});

  @override
  State<SelectDestinationMap> createState() => _SelectDestinationMapState();
}

class _SelectDestinationMapState extends State<SelectDestinationMap> {
  ll.LatLng? _selectedPoint;
  final MapController _mapController = MapController();

  MapLibreMapController? _mapLibreController;
  Symbol? _symbol;
  // maplibre_gl only allows adding annotations (symbols/lines) once the
  // style has actually finished loading — onMapCreated fires too early.
  bool _styleLoaded = false;

  Future<void> _onStyleLoaded() async {
    final controller = _mapLibreController;
    if (controller == null) return;
    final bytes = await buildPinMarkerBytes(color: Colors.red);
    await controller.addImage('pick-pin', bytes);
    setState(() => _styleLoaded = true);
  }

  Future<void> _onMapLibreClick(Point<double> point, LatLng latLng) async {
    final controller = _mapLibreController;
    if (controller == null || !_styleLoaded) return;

    if (_symbol == null) {
      _symbol = await controller.addSymbol(
        SymbolOptions(geometry: latLng, iconImage: 'pick-pin', iconSize: 0.6),
      );
    } else {
      await controller.updateSymbol(_symbol!, SymbolOptions(geometry: latLng));
    }

    setState(
        () => _selectedPoint = ll.LatLng(latLng.latitude, latLng.longitude));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tap a location on the map')),
      body: Stack(
        children: [
          use3DMap
              ? MapLibreMap(
                  styleString: mapStyleUrl,
                  onMapCreated: (controller) =>
                      _mapLibreController = controller,
                  onStyleLoadedCallback: _onStyleLoaded,
                  onMapClick: _onMapLibreClick,
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(_kInitialLat, _kInitialLng),
                    zoom: 13.0,
                    tilt: 45,
                  ),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const ll.LatLng(_kInitialLat, _kInitialLng),
                    initialZoom: 13.0,
                    onTap: (tapPosition, point) {
                      setState(() => _selectedPoint = point);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'fast_travel',
                      subdomains: const ['a', 'b', 'c'],
                    ),
                    if (_selectedPoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedPoint!,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on,
                                color: Colors.red, size: 40),
                          ),
                        ],
                      ),
                  ],
                ),
          if (_selectedPoint != null)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: () {
                  widget.onLocationSelected(_selectedPoint!);
                  Navigator.pop(context);
                },
                child: const Text('Confirm this location'),
              ),
            ),
        ],
      ),
    );
  }
}
