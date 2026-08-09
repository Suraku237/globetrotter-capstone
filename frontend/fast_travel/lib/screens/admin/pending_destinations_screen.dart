import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';

class PendingDestinationsScreen extends StatefulWidget {
  const PendingDestinationsScreen({super.key});

  @override
  State<PendingDestinationsScreen> createState() =>
      _PendingDestinationsScreenState();
}

class _PendingDestinationsScreenState extends State<PendingDestinationsScreen> {
  List<Destination> _pending = [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

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
      final pending = await ApiService.instance.getPendingDestinations();
      setState(() => _pending = pending);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Destination destination, bool approve) async {
    setState(() => _busy.add(destination.id));
    try {
      if (approve) {
        await ApiService.instance.approveDestination(destination.id);
      } else {
        await ApiService.instance.rejectDestination(destination.id);
      }
      setState(() => _pending.removeWhere((d) => d.id == destination.id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this submission.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(destination.id));
    }
  }

  Future<void> _edit(Destination destination) async {
    final updated = await showDialog<Destination>(
      context: context,
      builder: (context) => _EditDestinationDialog(destination: destination),
    );
    if (updated != null) {
      setState(() {
        final index = _pending.indexWhere((d) => d.id == updated.id);
        if (index != -1) _pending[index] = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sand,
      appBar: AppBar(title: const Text('Review destination submissions')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: "Can't reach the server",
                    message: _error!,
                    onRetry: _load,
                  )
                : _pending.isEmpty
                    ? const EmptyState(
                        icon: Icons.task_alt_rounded,
                        title: 'Nothing pending',
                        message: 'All destination submissions have been reviewed.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _pending.length,
                          itemBuilder: (context, index) {
                            final destination = _pending[index];
                            final busy = _busy.contains(destination.id);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 14),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (destination.imageUrl != null)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Image.network(
                                          '${ApiService.baseUrl}${destination.imageUrl}',
                                          height: 160,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              Container(
                                            height: 160,
                                            color: AppColors.sandDim,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                                Icons.image_not_supported_rounded,
                                                color: AppColors.inkSoft),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(destination.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium),
                                        ),
                                        IconButton(
                                          tooltip: 'Edit details',
                                          icon: const Icon(Icons.edit_rounded,
                                              size: 20),
                                          onPressed: busy
                                              ? null
                                              : () => _edit(destination),
                                        ),
                                      ],
                                    ),
                                    Text(destination.region.toUpperCase(),
                                        style:
                                            Theme.of(context).textTheme.labelSmall),
                                    const SizedBox(height: 8),
                                    Text(destination.description,
                                        style:
                                            Theme.of(context).textTheme.bodyMedium),
                                    if (destination.tags.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: destination.tags
                                            .map((t) => Chip(
                                                  label: Text(t,
                                                      style: const TextStyle(
                                                          fontSize: 11)),
                                                  padding: EdgeInsets.zero,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  backgroundColor:
                                                      AppColors.sandDim,
                                                  side: BorderSide.none,
                                                ))
                                            .toList(),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      '${destination.lat.toStringAsFixed(4)}, ${destination.lng.toStringAsFixed(4)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                    const SizedBox(height: 12),
                                    if (busy)
                                      const Center(
                                          child: CircularProgressIndicator())
                                    else
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  _decide(destination, false),
                                              child: const Text('Reject'),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () =>
                                                  _decide(destination, true),
                                              child: const Text('Approve'),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}

class _EditDestinationDialog extends StatefulWidget {
  final Destination destination;
  const _EditDestinationDialog({required this.destination});

  @override
  State<_EditDestinationDialog> createState() =>
      _EditDestinationDialogState();
}

class _EditDestinationDialogState extends State<_EditDestinationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _region;
  late final TextEditingController _description;
  late final TextEditingController _tags;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.destination;
    _name = TextEditingController(text: d.name);
    _region = TextEditingController(text: d.region);
    _description = TextEditingController(text: d.description);
    _tags = TextEditingController(text: d.tags.join(', '));
  }

  @override
  void dispose() {
    _name.dispose();
    _region.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ApiService.instance.updateDestination(
        widget.destination.id,
        name: _name.text.trim(),
        region: _region.text.trim(),
        description: _description.text.trim(),
        tags: _tags.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Edit destination',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: AppColors.clay)),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _region,
                    decoration: const InputDecoration(labelText: 'Region'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 3,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _tags,
                    decoration: const InputDecoration(
                      labelText: 'Tags',
                      hintText: 'comma, separated, tags',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save'),
                      ),
                    ],
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
