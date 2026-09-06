import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../Services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import 'itinerary_map_screen.dart';

class ItinerariesScreen extends StatefulWidget {
  // When set (e.g. from the "Plan Trip" button on a destination's detail
  // page), the create-itinerary dialog opens automatically with this
  // destination already selected instead of landing on a blank list.
  final Destination? presetDestination;
  // Optional text to pre-fill the itinerary's notes field with — used to
  // carry the "what to bring" essentials from the destination detail
  // screen into the plan so the user doesn't have to retype them. Still
  // fully editable; it's just a starting point.
  final String? presetNotes;

  const ItinerariesScreen({
    super.key,
    this.presetDestination,
    this.presetNotes,
  });

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
    if (widget.presetDestination != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openCreateDialog(
            preset: widget.presetDestination,
            presetNotes: widget.presetNotes,
          );
        }
      });
    }
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

  Future<void> _openCreateDialog({
    Destination? preset,
    String? presetNotes,
  }) async {
    // Make sure the preset destination is actually in the dropdown's
    // options even if it isn't one of the currently-loaded/fallback ones
    // (e.g. a brand-new suggestion) — otherwise preselecting its id would
    // silently do nothing.
    var options = _getSafeDestinations();
    if (preset != null && options.every((d) => d.id != preset.id)) {
      options = [preset, ...options];
    }
    final created = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.canopy.withValues(alpha: 0.72),
      builder: (_) => _CreateItineraryDialog(
        destinations: options,
        preselectedDestinationId: preset?.id,
        initialNotes: presetNotes,
      ),
    );
    if (created == true && mounted) _load();
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
                    // Two stacked rows instead of one long one: cramming the
                    // thumbnail, title/date, countdown AND a labeled button
                    // into a single Row doesn't fit on phone-width screens —
                    // the fixed-width pieces alone (image + countdown +
                    // button) already exceed ~290px, so the title column
                    // (the only flexible part) gets squeezed to nothing and
                    // the row overflows on anything narrower than ~360dp.
                    // Splitting into "info" then "countdown + action" keeps
                    // every piece full width to work with on any screen.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 50,
                                height: 50,
                                child: Image.network(
                                  ApiService.resolveUrl(
                                      destination.imageUrl ?? ''),
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
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_destinationName(it.destinationId)}  ·  ${it.startDate} → ${it.endDate}',
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
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
                            icon:
                                const Icon(Icons.directions_rounded, size: 16),
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
  final String? preselectedDestinationId;
  final String? initialNotes;
  const _CreateItineraryDialog({
    required this.destinations,
    this.preselectedDestinationId,
    this.initialNotes,
  });

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

  @override
  void initState() {
    super.initState();
    _destinationId = widget.preselectedDestinationId;
    // Pre-fill the notes with the caller-provided starter text (the
    // destination detail screen passes the "what to bring" essentials
    // here). Only applied when non-empty so the placeholder still shows
    // for a plain trip creation opened from the empty state.
    final seed = widget.initialNotes?.trim();
    if (seed != null && seed.isNotEmpty) {
      _notes.text = seed;
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime? date) {
    if (date == null) return 'Select date';
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = isStart ? today : (_start ?? today);
    var initialDate = isStart ? (_start ?? today) : (_end ?? _start ?? today);
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: today.add(const Duration(days: 730)),
      helpText: isStart ? 'SELECT START DATE' : 'SELECT END DATE',
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = null;
      } else {
        _end = picked;
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final formIsValid = _formKey.currentState?.validate() ?? false;
    final datesAreValid = _start != null && _end != null;

    if (!formIsValid || !datesAreValid) {
      setState(() {
        _error = datesAreValid ? null : 'Choose your start and end dates.';
      });
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

      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (error, stackTrace) {
      debugPrint('Creating itinerary failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not reach the server.';
      });
    }
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onPressed,
  }) {
    final hasDate = date != null;

    return Semantics(
      button: true,
      label: label,
      value: _displayDate(date),
      child: OutlinedButton(
        onPressed: _loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: hasDate
              ? AppColors.ochre.withValues(alpha: 0.08)
              : AppColors.sandDim,
          minimumSize: const Size.fromHeight(64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          side: BorderSide(
            color: hasDate
                ? AppColors.ochre.withValues(alpha: 0.65)
                : AppColors.ink.withValues(alpha: 0.1),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_month_rounded,
              color: hasDate ? AppColors.ochre : AppColors.inkSoft,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _displayDate(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: hasDate ? AppColors.ink : AppColors.inkSoft,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    final cancelButton = OutlinedButton(
      onPressed: _loading ? null : () => Navigator.of(context).pop(false),
      child: const Text('Cancel'),
    );
    final saveButton = ElevatedButton(
      onPressed: _loading ? null : _submit,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _loading
            ? const Row(
                key: ValueKey('saving'),
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Saving...'),
                ],
              )
            : const Row(
                key: ValueKey('save'),
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Save trip'),
                ],
              ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 52, child: saveButton),
              const SizedBox(height: 10),
              SizedBox(height: 52, child: cancelButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: SizedBox(height: 52, child: cancelButton)),
            const SizedBox(width: 12),
            Expanded(child: SizedBox(height: 52, child: saveButton)),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_loading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Material(
            color: AppColors.sand,
            elevation: 24,
            shadowColor: AppColors.canopy.withValues(alpha: 0.35),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 22, 16, 22),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.canopy, AppColors.canopyLight],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.ochre.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: AppColors.ochre.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.flight_takeoff_rounded,
                            color: AppColors.ochre,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Plan a trip',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Turn your next destination into an itinerary.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.72),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).pop(false),
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor:
                                Colors.white.withValues(alpha: 0.35),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip details',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _title,
                            enabled: !_loading,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Trip title',
                              hintText: 'e.g. Weekend in Limbe',
                              prefixIcon: Icon(Icons.luggage_rounded),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                    ? 'Enter a trip title'
                                    : null,
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _destinationId,
                            isExpanded: true,
                            menuMaxHeight: 320,
                            borderRadius: BorderRadius.circular(16),
                            dropdownColor: AppColors.sand,
                            decoration: const InputDecoration(
                              labelText: 'Destination',
                              prefixIcon: Icon(Icons.place_rounded),
                            ),
                            items: widget.destinations.map((destination) {
                              final region = destination.region.trim();
                              final label = region.isEmpty
                                  ? destination.name
                                  : '${destination.name} • $region';
                              return DropdownMenuItem<String>(
                                value: destination.id,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: _loading
                                ? null
                                : (destinationId) {
                                    setState(() {
                                      _destinationId = destinationId;
                                      _error = null;
                                    });
                                  },
                            validator: (value) =>
                                value == null ? 'Choose a destination' : null,
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'Travel dates',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Choose when your adventure starts and ends.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.inkSoft),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final startDate = _buildDateField(
                                label: 'START DATE',
                                date: _start,
                                onPressed: () => _pickDate(isStart: true),
                              );
                              final endDate = _buildDateField(
                                label: 'END DATE',
                                date: _end,
                                onPressed: () => _pickDate(isStart: false),
                              );

                              if (constraints.maxWidth < 380) {
                                return Column(
                                  children: [
                                    startDate,
                                    const SizedBox(height: 10),
                                    endDate,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: startDate),
                                  const SizedBox(width: 12),
                                  Expanded(child: endDate),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _notes,
                            enabled: !_loading,
                            textCapitalization: TextCapitalization.sentences,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Notes (optional)',
                              hintText: 'Add reminders, activities, or ideas',
                              alignLabelWithHint: true,
                              prefixIcon: Padding(
                                padding: EdgeInsets.only(bottom: 42),
                                child: Icon(Icons.notes_rounded),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.clay.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppColors.clay.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: AppColors.clay,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: AppColors.clay),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          _buildActions(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
