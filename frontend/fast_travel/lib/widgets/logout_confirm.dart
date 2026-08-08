import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared confirmation dialog shown before signing out — used by every
/// role (user, admin, worker) so no sign-out button skips it.
Future<bool> confirmSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text("You'll need to sign in again to use the app."),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign out', style: TextStyle(color: AppColors.clay)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
