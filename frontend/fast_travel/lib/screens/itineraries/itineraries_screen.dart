import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import 'map_view_screen.dart'; // ✅ UPDATED: Now points to the standalone map screen

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.getItineraries(),
        ApiService.instance.getDestinations(),
      ]);
      setState(() {
        _items = results[0] as List<Itinerary>;
        _destinations = results[1] as List<Destination>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
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
          imageAsset: '',
          description: '',
        ),
      )
      .name;

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateItineraryDialog(destinations: _destinations),
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
            icon: Icons.wifi_off_rounded,
            title: "Can't reach the server",
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
                    imageAsset: '',
                    description: '',
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
                        // Leading Icon (Car)
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.teal,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.directions_car_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Trip Info (Title, Destination, Dates)
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

                        // ✅ VISIBLE "MAP" BUTTON (Now opens MapViewScreen)
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MapViewScreen(
                                  destLat: 3.9004,
                                  destLng: 11.5489,
                                  destName: destination.name,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.map, size: 16),
                          label: const Text('Map'),
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
      await ApiService.instance.createItinerary(
        title: _title.text.trim(),
        destinationId: _destinationId!,
        startDate: _fmt(_start!),
        endDate: _fmt(_end!),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
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
      backgroundColor: AppColors.sand,
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
                  initialValue: _destinationId,
                  decoration: const InputDecoration(labelText: 'Destination'),
                  items: widget.destinations
                      .map((d) => DropdownMenuItem(
                          value: d.id, child: Text('${d.name} (${d.region})')))
                      .toList(),
                  onChanged: (v) => setState(() => _destinationId = v),
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
