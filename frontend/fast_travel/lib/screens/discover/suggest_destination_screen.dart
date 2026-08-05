import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../Services/api_service.dart';
import '../../theme/app_theme.dart';
import '../itineraries/select_destination_map.dart';

class SuggestDestinationScreen extends StatefulWidget {
  const SuggestDestinationScreen({super.key});

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
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _image = picked;
      _imagePreview = bytes;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) {
      setState(() => _error = 'Pick a location on the map first.');
      return;
    }
    if (_image == null) {
      setState(() => _error = 'Add a photo first.');
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Submitted — a worker or admin will review it soon.'),
          ),
        );
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
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
    return Scaffold(
      backgroundColor: AppColors.sand,
      appBar: AppBar(title: const Text('Suggest a destination')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.clay)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 4,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickLocation,
                icon: const Icon(Icons.location_on_outlined),
                label: Text(
                  _location == null
                      ? 'Pick location on map'
                      : 'Location: ${_location!.latitude.toStringAsFixed(4)}, ${_location!.longitude.toStringAsFixed(4)}',
                ),
              ),
              const SizedBox(height: 12),
              if (_imagePreview != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    _imagePreview!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(_image == null ? 'Add a photo' : 'Change photo'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit for review'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
