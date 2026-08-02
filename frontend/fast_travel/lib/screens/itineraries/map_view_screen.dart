import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapViewScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📍 $destName'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(destLat, destLng),
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
                point: LatLng(destLat, destLng),
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
