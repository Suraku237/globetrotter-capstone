import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  // Defaults to the localized "Try again" (resolved in build(), since a
  // constructor default can't depend on BuildContext) — pass a value here
  // only to override that default wording.
  final String? retryLabel;
  // Screens with a dark/near-black background (e.g. the video feed) need
  // light text here instead of the default dark-on-light styling, or the
  // whole state becomes unreadable.
  final bool light;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = light ? Colors.white70 : AppColors.inkSoft;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          color: light ? Colors.white : null,
        );
    final messageStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: light ? Colors.white70 : null,
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: iconColor),
            const SizedBox(height: 12),
            Text(title, style: titleStyle),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: messageStyle,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                style: light
                    ? OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                      )
                    : null,
                child:
                    Text(retryLabel ?? AppLocalizations.of(context)!.tryAgain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
