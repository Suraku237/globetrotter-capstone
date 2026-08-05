import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../widgets/map_marker_icon.dart';
import '../../widgets/map_platform.dart';

class MapViewScreen extends StatefulWidget {
  final double destLat;
  final double destLng;
  final String destName;

  const MapViewScreen({
    super.key,
    required this.destLat,
    required this.destLng,
    required this.destName,
  });

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  MapLibreMapController? _controller;

  // maplibre_gl only allows adding annotations (symbols/lines) once the
  // style has actually finished loading — onMapCreated fires too early.
  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;
    final bytes = await buildPinMarkerBytes(color: Colors.red);
    await controller.addImage('dest-pin', bytes);
    await controller.addSymbol(
      SymbolOptions(
        geometry: LatLng(widget.destLat, widget.destLng),
        iconImage: 'dest-pin',
        iconSize: 0.6,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📍 ${widget.destName}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: use3DMap
          ? MapLibreMap(
              styleString: mapStyleUrl,
              onMapCreated: (controller) => _controller = controller,
              onStyleLoadedCallback: _onStyleLoaded,
              initialCameraPosition: CameraPosition(
                target: LatLng(widget.destLat, widget.destLng),
                zoom: 15.0,
                tilt: 45,
              ),
            )
          : FlutterMap(
              options: MapOptions(
                initialCenter: ll.LatLng(widget.destLat, widget.destLng),
                initialZoom: 15.0,
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
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 50,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
