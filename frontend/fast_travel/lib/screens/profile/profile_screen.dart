import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../Services/api_service.dart';
import '../../Services/locale_controller.dart';
import '../../Services/session_state.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/logout_confirm.dart';

class ProfileScreen extends StatefulWidget {
  final SessionState session;
  final LocaleController localeController;
  // True when shown as the Profile tab inside AdaptiveShell, which already
  // renders a title bar — a nested AppBar here would show it twice. False
  // (default) when pushed as its own route, e.g. from the worker home
  // screen, where it needs its own AppBar for the back button.
  final bool embedded;
  const ProfileScreen({
    super.key,
    required this.session,
    required this.localeController,
    this.embedded = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _savingName = false;
  bool _uploadingAvatar = false;
  String? _error;

  Future<void> _editName() async {
    final l10n = AppLocalizations.of(context)!;
    final controller =
        TextEditingController(text: widget.session.currentUser?.fullName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.editName),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.fullNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.save),
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

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silent — nothing meaningful to recover into if the platform can't
      // open it (e.g. no mail client configured).
    }
  }

  Future<void> _showAboutDeveloper() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('About the developer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.ochre,
                child: Text(
                  'KJ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Kwete Ngnouba Junior Rayan',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Text(
                'Full-Stack Developer · Flutter & FastAPI',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text(
                'Building Fast Travel end to end — Flutter on the front, '
                'FastAPI on the back, and everything in between: from the '
                'itinerary engine to the pipeline that ships it. Based in '
                'Yaoundé, currently studying Software Engineering at ICT '
                'University.',
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.code_rounded),
                title: const Text('GitHub'),
                onTap: () => _openUrl('https://github.com/Suraku237'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.work_outline_rounded),
                title: const Text('LinkedIn'),
                onTap: () => _openUrl(
                    'https://www.linkedin.com/in/kwete-ngnouba-junior-rayan-643b97402/'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email'),
                onTap: () => _openUrl('mailto:kwetejunior9@gmail.com'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRateUs() async {
    int selected = 0;
    final submitted = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Rate Fast Travel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('How has your experience been?'),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < selected;
                  return IconButton(
                    onPressed: () => setDialogState(() => selected = i + 1),
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      color: AppColors.ochre,
                      size: 32,
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selected == 0
                  ? null
                  : () => Navigator.pop(dialogContext, selected),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (submitted == null || !mounted) return;
    _openUrl(
      'mailto:kwetejunior9@gmail.com?subject=${Uri.encodeComponent('Fast Travel rating: $submitted star${submitted == 1 ? '' : 's'}')}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks for your feedback!')),
    );
  }

  Future<void> _changeAvatar() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
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
    final l10n = AppLocalizations.of(context)!;
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
                  subtitle: Text(l10n.displayName),
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
                  subtitle: Text(l10n.emailLabel),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text((user?.role ?? 'user').toUpperCase()),
                  subtitle: Text(l10n.roleFieldLabel),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text(l10n.language),
                  trailing: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                          value: 'en', label: Text(l10n.languageEnglish)),
                      ButtonSegment(
                          value: 'fr', label: Text(l10n.languageFrench)),
                    ],
                    selected: {widget.localeController.locale.languageCode},
                    onSelectionChanged: (selected) =>
                        widget.localeController.setLanguageCode(selected.first),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('About the developer'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showAboutDeveloper,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.star_outline_rounded),
                  title: const Text('Rate us'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showRateUs,
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
                label: Text(l10n.signOut),
              ),
            ],
          ),
        );

        if (widget.embedded) return body;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(l10n.titleProfile)),
          body: body,
        );
      },
    );
  }
}
