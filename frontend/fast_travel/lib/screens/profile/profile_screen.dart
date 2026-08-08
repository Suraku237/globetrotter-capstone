import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../Services/api_service.dart';
import '../../Services/session_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/logout_confirm.dart';

class ProfileScreen extends StatefulWidget {
  final SessionState session;
  // True when shown as the Profile tab inside AdaptiveShell, which already
  // renders a title bar — a nested AppBar here would show it twice. False
  // (default) when pushed as its own route, e.g. from the worker home
  // screen, where it needs its own AppBar for the back button.
  final bool embedded;
  const ProfileScreen({super.key, required this.session, this.embedded = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _savingName = false;
  bool _uploadingAvatar = false;
  String? _error;

  Future<void> _editName() async {
    final controller =
        TextEditingController(text: widget.session.currentUser?.fullName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    setState(() {
      _savingName = true;
      _error = null;
    });
    try {
      await widget.session.updateProfile(fullName: newName);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changeAvatar() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _uploadingAvatar = true;
      _error = null;
    });
    try {
      await widget.session.updateProfile(avatarFile: picked);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final user = widget.session.currentUser;
        final avatarUrl = user?.avatarUrl;

        final body = SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 56,
                        backgroundColor: AppColors.sandDim,
                        backgroundImage: avatarUrl != null
                            ? NetworkImage('${ApiService.baseUrl}$avatarUrl')
                            : null,
                        child: avatarUrl == null
                            ? const Icon(Icons.person_rounded,
                                size: 56, color: AppColors.inkSoft)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _uploadingAvatar ? null : _changeAvatar,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.ochre,
                            child: _uploadingAvatar
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.camera_alt_rounded,
                                    size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.clay),
                        textAlign: TextAlign.center),
                  ),
                Card(
                  child: ListTile(
                    title: Text(user?.fullName ?? ''),
                    subtitle: const Text('Display name'),
                    trailing: _savingName
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.edit_rounded),
                            onPressed: _editName,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: Text(user?.email ?? ''),
                    subtitle: const Text('Email'),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: Text((user?.role ?? 'user').toUpperCase()),
                    subtitle: const Text('Role'),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (!await confirmSignOut(context)) return;
                    widget.session.signOut();
                    if (context.mounted) {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
            ],
          ),
        );

        if (widget.embedded) return body;
        return Scaffold(
          backgroundColor: AppColors.sand,
          appBar: AppBar(title: const Text('Profile')),
          body: body,
        );
      },
    );
  }
}
