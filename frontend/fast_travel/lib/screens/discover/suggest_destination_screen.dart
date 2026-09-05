import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../Services/api_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../itineraries/select_destination_map.dart';

// Pushed as a full page with Navigator.push rather than showDialog — it
// used to be a modal, but adding a photo picker, a map picker, and a
// description field made it cramped inside a dialog on phones and web
// tabs. As a page it also gets the standard back-button/gesture, which
// showDialog doesn't provide.
class SuggestDestinationScreen extends StatefulWidget {
  // Admins add a destination directly — there's no one else who needs to
  // review their own submission (see POST /destinations on the backend,
  // which auto-approves for the admin role). Everyone else submits it for
  // review. This only changes the wording shown; the form/fields/logic
  // are otherwise identical.
  final bool isAdmin;
  const SuggestDestinationScreen({super.key, this.isAdmin = false});

  @override
  State<SuggestDestinationScreen> createState() =>
      _SuggestDestinationScreenState();
}

class _SuggestDestinationScreenState extends State<SuggestDestinationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  LatLng? _location;
  XFile? _image;
  Uint8List? _imagePreview;
  bool _submitting = false;
  String? _error;

  Future<void> _pickLocation() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SelectDestinationMap(
          onLocationSelected: (point) => setState(() => _location = point),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _image = picked;
      _imagePreview = bytes;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    if (_location == null) {
      setState(() => _error = l10n.pickLocationFirst);
      return;
    }
    if (_image == null) {
      setState(() => _error = l10n.addPhotoFirst);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiService.instance.submitDestination(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        lat: _location!.latitude,
        lng: _location!.longitude,
        image: _image!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = l10n.couldNotReachServerShort);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title =
        widget.isAdmin ? l10n.addDestination : l10n.suggestDestination;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        // Explicitly return false when the user backs out with the app
        // bar back button so the caller's ".then((submitted) => ...)"
        // sees a matching sentinel rather than null.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(false),
          tooltip: l10n.cancel,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Text(_error!,
                          style: const TextStyle(color: AppColors.clay)),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _nameController,
                      decoration:
                          InputDecoration(labelText: l10n.destinationNameLabel),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? l10n.requiredField
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _descriptionController,
                      decoration:
                          InputDecoration(labelText: l10n.descriptionLabel),
                      maxLines: 3,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? l10n.requiredField
                          : null,
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _pickLocation,
                      icon: const Icon(Icons.location_on_outlined),
                      label: Text(
                        _location == null
                            ? l10n.pickLocationOnMap
                            : l10n.locationSelected(
                                _location!.latitude.toStringAsFixed(4),
                                _location!.longitude.toStringAsFixed(4),
                              ),
                      ),
                    ),
                    if (_imagePreview != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          _imagePreview!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                          _image == null ? l10n.addPhoto : l10n.changePhoto),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(l10n.cancel),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(widget.isAdmin
                                  ? l10n.addDestination
                                  : l10n.submitForReview),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
