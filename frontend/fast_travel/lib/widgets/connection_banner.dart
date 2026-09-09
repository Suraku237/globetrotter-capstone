import 'package:flutter/material.dart';

import '../Services/api_service.dart';
import '../Services/media_settings.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final api = ApiService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([
        api.liveStatus,
        api.networkUnavailable,
        api.cacheStorageWarning,
        MediaSettings.instance,
      ]),
      builder: (context, _) {
        final french = Localizations.localeOf(context).languageCode == 'fr';
        final offline = api.networkUnavailable.value;
        final storage = api.cacheStorageWarning.value ||
            MediaSettings.instance.storageError != null;
        final show = storage || (api.isAuthenticated && (!api.isLive || offline));
        return Column(
          children: [
            if (show)
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Row(
                      children: [
                        Icon(offline ? Icons.cloud_off : Icons.sync, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            storage
                                ? (french
                                    ? 'Cache indisponible sur cet appareil.'
                                    : 'Cannot save offline content on this device.')
                                : offline
                                    ? (french
                                        ? 'Hors ligne - contenu enregistre.'
                                        : 'Offline - showing saved content.')
                                    : (french
                                        ? 'Reconnexion aux mises a jour en direct...'
                                        : 'Reconnecting live updates...'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: api.retryConnection,
                          child: Text(french ? 'Reessayer' : 'Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
