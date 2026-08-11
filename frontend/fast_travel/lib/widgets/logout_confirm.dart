import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// Shared confirmation dialog shown before signing out — used by every
/// role (user, admin, worker) so no sign-out button skips it.
Future<bool> confirmSignOut(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.signOutConfirmTitle),
      content: Text(l10n.signOutConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child:
              Text(l10n.signOut, style: const TextStyle(color: AppColors.clay)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
