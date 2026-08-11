import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../Services/api_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../itineraries/select_destination_map.dart';

// Shown via showDialog(...) rather than pushed as a full screen — a
// destination suggestion is a quick, occasional action and doesn't warrant
// its own screen, matching how "Plan a trip" works on the itineraries tab.
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
    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      widget.isAdmin
                          ? l10n.addDestination
                          : l10n.suggestDestination,
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
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label:
                        Text(_image == null ? l10n.addPhoto : l10n.changePhoto),
                  ),
                  const SizedBox(height: 20),
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
    );
  }
}
