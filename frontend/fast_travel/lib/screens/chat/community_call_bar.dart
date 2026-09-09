import 'dart:async';

import 'package:flutter/material.dart';

import '../../Services/api_service.dart';
import '../../Services/call_coordinator.dart';
import '../../models/call_models.dart';
import '../../theme/app_theme.dart';
import 'chat_ui.dart';

/// Public room calls are opt-in: discovering one never accepts or rings it.
class CommunityCallBar extends StatefulWidget {
  const CommunityCallBar({
    super.key,
    required this.beforeCall,
    this.api,
    this.calls,
  });

  final Future<bool> Function() beforeCall;
  final ApiService? api;
  final CallCoordinator? calls;

  @override
  State<CommunityCallBar> createState() => _CommunityCallBarState();
}

class _CommunityCallBarState extends State<CommunityCallBar> {
  ApiService get _api => widget.api ?? ApiService.instance;
  CallCoordinator get _calls => widget.calls ?? CallCoordinator.instance;
  late final ChatRefreshController _updates;
  CallSession? _active;
  String? _error;
  bool _loading = true;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _updates = ChatRefreshController(
      changes: _api.changes,
      topics: const {'community_calls'},
      isLive: () => _api.isLive,
      isVisible: () => mounted && TickerMode.of(context) &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      invalidate: _api.refreshTopics,
      load: _load,
    )..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updates.visibilityChanged();
  }

  Future<void> _load() async {
    try {
      final active = await _api.getCommunityCall();
      if (!mounted) return;
      setState(() {
        _active = active?.isEnded == true ? null : active;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _active = null;
          _error = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startOrJoin(CallKind kind) async {
    if (_joining || _calls.isInCall) return;
    setState(() => _joining = true);
    try {
      if (!await widget.beforeCall() || !mounted) return;
      final active = _active;
      if (active != null) {
        await _calls.joinCommunityCall(active.id);
      } else {
        await _calls.startCall(
            kind: kind, targetType: 'community', targetId: 'community');
      }
    } finally {
      if (mounted) {
        setState(() => _joining = false);
        unawaited(_updates.refresh());
      }
    }
  }

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CallSession?>(
        valueListenable: _calls.callState,
        builder: (context, localCall, _) {
          final active = _active;
          final busy = _joining || _calls.isInCall;
          return Material(
            color: AppColors.sand.withValues(alpha: 0.94),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    active == null
                        ? chatLabel(context, 'Community calls', 'Appels communautaires')
                        : chatLabel(context,
                            '${active.kind == CallKind.video ? 'Video' : 'Voice'} call - ${active.acceptedIds.length} joined',
                            'Appel ${active.kind == CallKind.video ? 'video' : 'vocal'} - ${active.acceptedIds.length} participants'),
                    style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                  else if (_error != null)
                    Row(children: [
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: AppColors.inkSoft, fontSize: 12))),
                      TextButton(onPressed: _updates.refreshFromNetwork,
                          child: Text(chatLabel(context, 'Retry', 'Reessayer'))),
                    ])
                  else if (active != null)
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: busy ? null : () => _startOrJoin(active.kind),
                          icon: Icon(active.kind == CallKind.video
                              ? Icons.videocam_rounded : Icons.call_rounded),
                          label: Text(chatLabel(context, 'Join call', "Rejoindre l'appel")),
                        ),
                        Text(chatLabel(context, 'Join only if you want to.',
                            'Participation facultative.'),
                            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: busy ? null : () => _startOrJoin(CallKind.voice),
                          icon: const Icon(Icons.call_rounded),
                          label: Text(chatLabel(context, 'Voice call', 'Appel vocal')),
                        ),
                        TextButton.icon(
                          onPressed: busy ? null : () => _startOrJoin(CallKind.video),
                          icon: const Icon(Icons.videocam_rounded),
                          label: Text(chatLabel(context, 'Video call', 'Appel video')),
                        ),
                      ],
                    ),
                  if (_joining)
                    const LinearProgressIndicator(minHeight: 2)
                  else if (localCall != null)
                    Text(chatLabel(context, 'Finish your current call first.',
                        "Terminez d'abord votre appel en cours."),
                        style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                ],
              ),
            ),
          );
        },
      );
}
