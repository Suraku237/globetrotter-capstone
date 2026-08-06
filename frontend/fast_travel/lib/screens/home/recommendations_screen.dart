import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../Services/api_service.dart';
import '../../widgets/destination_card.dart';
import '../../widgets/empty_state.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  List<Destination> _items = [];
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
      final results = await ApiService.instance.getRecommendations();
      setState(() => _items = results);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: "Can't reach the server",
        message: _error!,
        onRetry: _load,
      );
    }
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.auto_awesome_outlined,
        title: 'No recommendations yet',
        message:
            'Save a few destinations you like and we\'ll tailor picks for you.',
        onRetry: _load,
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 1024
        ? 4
        : (width >= 700 ? 3 : (width >= 500 ? 2 : 1));

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.92,
        ),
        itemCount: _items.length,
        itemBuilder: (context, i) => DestinationCard(destination: _items[i]),
      ),
    );
  }
}
