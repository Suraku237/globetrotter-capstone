import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class SelectDestinationMap extends StatefulWidget {
  final Function(LatLng) onLocationSelected;

  const SelectDestinationMap({super.key, required this.onLocationSelected});

  @override
  State<SelectDestinationMap> createState() => _SelectDestinationMapState();
}

class _SelectDestinationMapState extends State<SelectDestinationMap> {
  LatLng? _selectedPoint;
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tap a location on the map')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(3.8480, 11.5021),
              initialZoom: 13.0,
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedPoint = point;
                });
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
