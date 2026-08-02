import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

class ExploreMapScreen extends StatefulWidget {
  const ExploreMapScreen({super.key});

  @override
  State<ExploreMapScreen> createState() => _ExploreMapScreenState();
}

class _ExploreMapScreenState extends State<ExploreMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _currentLocation;
  bool _loadingLocation = false;
  bool _loadingDestinations = true;

  bool _isLocationEnabled = false;
  bool _isWaitingForPermission = false;

  List<Destination> _allDestinations = [];
  List<Destination> _searchResults = [];

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
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _isLocationEnabled = true;
          _loadingLocation = false;
          _isWaitingForPermission = false;
        });
        _mapController.move(_currentLocation!, 16.0);
      }
    } catch (e) {
      setState(() {
        _currentLocation = const LatLng(3.8480, 11.5021);
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

  void _showErrorDialog(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
      appBar: AppBar(
        title: const Text('Explore Map'),
        backgroundColor: AppColors.sand,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
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
            Container(
              height: 280,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.clay.withOpacity(0.2)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _currentLocation ?? const LatLng(3.8480, 11.5021),
                    initialZoom: 13.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'fast_travel',
                      subdomains: const ['a', 'b', 'c'],
                    ),
                    if (_currentLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentLocation!,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.my_location,
                                color: Colors.blue, size: 40),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
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
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(8),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 60,
                                height: 60,
                                child: Image.asset(
                                  dest.imageAsset,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                    color: AppColors.canopy,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.image,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              dest.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              dest.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.clay),
                            ),
                            trailing: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 16),
                            onTap: () {
                              // Navigate to DestinationDetailScreen
                            },
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
