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
                                    Text(destination.name,
                                        style:
                                            Theme.of(context).textTheme.titleMedium),
                                    const SizedBox(height: 4),
                                    Text(destination.description,
                                        style:
                                            Theme.of(context).textTheme.bodyMedium),
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
