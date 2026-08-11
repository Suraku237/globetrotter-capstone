import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../Services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import 'itinerary_map_screen.dart';

class ItinerariesScreen extends StatefulWidget {
  const ItinerariesScreen({super.key});

  @override
  State<ItinerariesScreen> createState() => _ItinerariesScreenState();
}

class _ItinerariesScreenState extends State<ItinerariesScreen> {
  List<Itinerary> _items = [];
  List<Destination> _destinations = [];
  bool _loading = true;
  String? _error;
  bool _errorIsNetwork = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorIsNetwork = false;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.getItineraries(),
        ApiService.instance.getDestinations(),
      ]);
      setState(() {
        _items = results[0] as List<Itinerary>;
        _destinations = results[1] as List<Destination>;
        _loading = false;
      });
    } on ApiException catch (e) {
      // A 401 signs the user out and returns them to the login screen
      // (see ApiService.onUnauthorized in main.dart), so there's nothing
      // useful to show here — just avoid flashing a confusing error first.
      if (e.isUnauthorized) return;
      setState(() {
        _error = e.message;
        _errorIsNetwork = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Could not reach the server.';
        _errorIsNetwork = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _destinationName(String id) => _destinations
      .firstWhere(
        (d) => d.id == id,
        orElse: () => Destination(
          id: id,
          name: 'Unknown',
          region: '',
          tags: const [],
          description: '',
          lat: 0.0,
          lng: 0.0,
        ),
      )
      .name;

  String _getCountdown(String startDate) {
    try {
      final start = DateTime.parse(startDate);
      final now = DateTime.now();
      final difference = start.difference(now).inDays;
      if (difference < 0) return 'Started!';
      if (difference == 0) return 'Today!';
      return '$difference days';
    } catch (_) {
      return '--';
    }
  }

  List<Destination> _getSafeDestinations() {
    if (_destinations.isNotEmpty) return _destinations;

    return [
      Destination(
          id: 'dest_001',
          name: 'Olembe Stadium',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_002',
          name: 'Reunification Monument',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_003',
          name: 'National Museum of Cameroon',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_004',
          name: 'Mvog-Betsi Zoological Garden',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_005',
          name: 'Marché Mokolo',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_006',
          name: 'Basilique Marie-Reine-des-Apostres',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_007',
          name: 'Mont Febe',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_008',
          name: 'Douala',
          region: 'Littoral',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_009',
          name: 'Rond-Point Deido',
          region: 'Littoral',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_010',
          name: 'La Nouvelle Liberté',
          region: 'Littoral',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_011',
          name: 'Ekom Nkam Waterfalls',
          region: 'Littoral',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_012',
          name: 'Wouri River Bridge',
          region: 'Littoral',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_013',
          name: 'Mount Cameroon',
          region: 'Southwest',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_014',
          name: 'Limbe Beach',
          region: 'Southwest',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_015',
          name: 'Limbe Wildlife Centre',
          region: 'Southwest',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_016',
          name: 'Korup National Park',
          region: 'Southwest',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_017',
          name: 'Foumban',
          region: 'West',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_018',
          name: 'Foumban Royal Palace',
          region: 'West',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_019',
          name: 'Bafoussam',
          region: 'West',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_020',
          name: 'Dschang',
          region: 'West',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_021',
          name: 'Kribi',
          region: 'South',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_022',
          name: 'Lobé Waterfalls',
          region: 'South',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_023',
          name: 'Waza National Park',
          region: 'Far North',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_024',
          name: 'Rhumsiki',
          region: 'Far North',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_025',
          name: 'Garoua',
          region: 'North',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_026',
          name: 'Cathedral Sainte Therese',
          region: 'North',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_027',
          name: 'Ngaoundéré',
          region: 'Adamawa',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_028',
          name: 'Bamenda',
          region: 'Northwest',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_029',
          name: 'Bafut Palace',
          region: 'Northwest',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_030',
          name: 'Kumbo',
          region: 'Northwest',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_031',
          name: 'Charles Atangana Statue',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_032',
          name: 'Canal Olympia',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_033',
          name: 'Unity Palace',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_034',
          name: 'Our Lady of Victories Cathedral',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_035',
          name: 'Saint Peter and Paul Cathedral',
          region: 'Littoral',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_036',
          name: 'Le Pacha',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_037',
          name: 'Le Délice',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_038',
          name: 'Dja Wildlife Reserve',
          region: 'South',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_039',
          name: 'Havana Lounge',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_040',
          name: 'Mfoundi Lake',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_041',
          name: 'Mefou National Park',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_042',
          name: 'Meli Waterfalls',
          region: 'Littoral',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_043',
          name: 'Marche Mokolo Street Food',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_044',
          name: 'Reunification Monument Statue',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
      Destination(
          id: 'dest_045',
          name: 'Mfoundi Mall',
          region: 'Centre',
          tags: [],
          description: '',
          lat: 0.0,
          lng: 0.0),
    ];
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CreateItineraryDialog(destinations: _getSafeDestinations()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          EmptyState(
            icon: _errorIsNetwork
                ? Icons.wifi_off_rounded
                : Icons.error_outline_rounded,
            title: _errorIsNetwork
                ? "Can't reach the server"
                : 'Something went wrong',
            message: _error!,
            onRetry: _load,
          )
        else if (_items.isEmpty)
          EmptyState(
            icon: Icons.map_outlined,
            title: 'No trips planned yet',
            message: 'Create your first itinerary to start planning.',
            onRetry: _openCreateDialog,
            retryLabel: 'Plan a trip',
          )
        else
          RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 12, bottom: 96),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final it = _items[i];
                final destination = _destinations.firstWhere(
                  (d) => d.id == it.destinationId,
                  orElse: () => Destination(
                    id: it.destinationId,
                    name: 'Unknown',
                    region: '',
                    tags: const [],
                    description: '',
                    lat: 0.0,
                    lng: 0.0,
                  ),
                );

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: Image.network(
                              ApiService.resolveUrl(destination.imageUrl ?? ''),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                it.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_destinationName(it.destinationId)}  ·  ${it.startDate} → ${it.endDate}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Starts in',
                                style: TextStyle(fontSize: 10)),
                            Text(
                              _getCountdown(it.startDate),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ItineraryMapScreen(
                                  destLat: destination.lat,
                                  destLng: destination.lng,
                                  destName: destination.name,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.directions_rounded, size: 16),
                          label: const Text('Show path'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.ochre,
                            foregroundColor: AppColors.ink,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
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
        Positioned(
          right: 8,
          bottom: 8,
          child: FloatingActionButton.extended(
            onPressed: _openCreateDialog,
            backgroundColor: AppColors.ochre,
            icon: const Icon(Icons.add_rounded, color: AppColors.ink),
            label: const Text('Plan a trip',
                style: TextStyle(color: AppColors.ink)),
          ),
        ),
      ],
    );
  }
}

class _CreateItineraryDialog extends StatefulWidget {
  final List<Destination> destinations;
  const _CreateItineraryDialog({required this.destinations});

  @override
  State<_CreateItineraryDialog> createState() => _CreateItineraryDialogState();
}

class _CreateItineraryDialogState extends State<_CreateItineraryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();

  String? _destinationId;
  DateTime? _start;
  DateTime? _end;
  bool _loading = false;
  String? _error;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => isStart ? _start = picked : _end = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() ||
        _destinationId == null ||
        _start == null ||
        _end == null) {
      setState(() => _error = 'Fill in destination and both dates.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // ✅ We don't need to store the result, just call it
      await ApiService.instance.createItinerary(
        title: _title.text.trim(),
        destinationId: _destinationId!,
        startDate: _fmt(_start!),
        endDate: _fmt(_end!),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );

      // ✅ Close the dialog immediately
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // A 401 signs the user out (see ApiService.onUnauthorized in
      // main.dart) and the login screen takes over — just close the dialog
      // instead of showing an error that's about to disappear anyway.
      if (e.isUnauthorized) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan a trip',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Trip title'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _destinationId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Destination',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  items: widget.destinations.map((dest) {
                    return DropdownMenuItem<String>(
                      value: dest.id,
                      child: Text('${dest.name} (${dest.region})'),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _destinationId = newValue;
                    });
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: true),
                        child:
                            Text(_start == null ? 'Start date' : _fmt(_start!)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: false),
                        child: Text(_end == null ? 'End date' : _fmt(_end!)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notes,
                  decoration:
                      const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.clay)),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save trip'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
