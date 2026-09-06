import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../Services/api_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../itineraries/select_destination_map.dart';

// Warm dark-cocoa surface used across this dialog â€” matches the earthy
// travel-brand palette (canopy indigo elsewhere, ochre CTA everywhere),
// keeps the modal instantly recognizable, and reads well against the
// YaoundÃ© cityscape now that the global off-white veil is gone.
const _brownSurface = Color(0xFF3E2A1F);
const _brownSurfaceHi = Color(0xFF5A3E2C);
const _brownDivider = Color(0x33F5E9DA);

// Presented as a compact dialog (previously a full-page Scaffold) so
// adding a destination feels lightweight â€” the caller uses showDialog
// and still gets the same bool result over Navigator.pop.
class SuggestDestinationScreen extends StatefulWidget {
  // Admins add a destination directly â€” there's no one else who needs to
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
    if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
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

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppColors.sand.withValues(alpha: 0.75)),
      floatingLabelStyle: const TextStyle(color: AppColors.ochre),
      filled: true,
      fillColor: _brownSurfaceHi,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.ochre, width: 1.4),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title =
        widget.isAdmin ? l10n.addDestination : l10n.suggestDestination;
    final locationLabel = _location == null
        ? l10n.pickLocationOnMap
        : l10n.locationSelected(
            _location!.latitude.toStringAsFixed(4),
            _location!.longitude.toStringAsFixed(4),
          );

    // Compact modal: sized down from the previous full-page Scaffold so
    // "add a destination" is a lightweight action instead of a whole
    // screen takeover. Height is capped so the dialog scrolls internally
    // on small phones instead of running off the bottom of the viewport.
    final mediaSize = MediaQuery.of(context).size;
    final dialogMaxWidth = mediaSize.width < 500 ? mediaSize.width - 32 : 440.0;
    final dialogMaxHeight = mediaSize.height * 0.85;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      elevation: 0,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: dialogMaxWidth, maxHeight: dialogMaxHeight),
        child: Material(
          color: _brownSurface,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: AppColors.sand),
            child: IconTheme(
              data: const IconThemeData(color: AppColors.sand),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(title),
                  Flexible(
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.clay.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        AppColors.clay.withValues(alpha: 0.6),
                                  ),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.sand,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _nameController,
                              style: const TextStyle(color: AppColors.sand),
                              cursorColor: AppColors.ochre,
                              decoration:
                                  _fieldDecoration(l10n.destinationNameLabel),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? l10n.requiredField
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _descriptionController,
                              style: const TextStyle(color: AppColors.sand),
                              cursorColor: AppColors.ochre,
                              decoration:
                                  _fieldDecoration(l10n.descriptionLabel),
                              maxLines: 3,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? l10n.requiredField
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            _buildPickerTile(
                              icon: Icons.location_on_outlined,
                              label: locationLabel,
                              onTap: _submitting ? null : _pickLocation,
                              highlighted: _location != null,
                            ),
                            const SizedBox(height: 10),
                            if (_imagePreview != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.memory(
                                  _imagePreview!,
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            _buildPickerTile(
                              icon: Icons.image_outlined,
                              label: _image == null
                                  ? l10n.addPhoto
                                  : l10n.changePhoto,
                              onTap: _submitting ? null : _pickImage,
                              highlighted: _image != null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: _brownDivider),
                  _buildFooter(l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.sand,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed:
                _submitting ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded, color: AppColors.sand),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildPickerTile({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required bool highlighted,
  }) {
    return Material(
      color: highlighted
          ? AppColors.ochre.withValues(alpha: 0.18)
          : _brownSurfaceHi,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  color: highlighted ? AppColors.ochre : AppColors.sand,
                  size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: highlighted
                        ? AppColors.ochre
                        : AppColors.sand.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.sand.withValues(alpha: 0.6), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed:
                _submitting ? null : () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.sand),
            child: Text(l10n.cancel),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.ochre,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
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
    );
  }
}
