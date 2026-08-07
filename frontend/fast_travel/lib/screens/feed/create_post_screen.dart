import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../Services/api_service.dart';
import '../../theme/app_theme.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _textController = TextEditingController();
  XFile? _image;
  Uint8List? _imagePreview;
  XFile? _video;
  VideoPlayerController? _videoController;
  bool _posting = false;
  String? _error;

  // Photo and video are mutually exclusive — a post carries one piece of
  // media, matching how the feed displays it.
  Future<void> _pickImage() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _clearVideo();
    setState(() {
      _image = picked;
      _imagePreview = bytes;
    });
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    // On web, XFile.path is a blob: URL playable directly; on mobile/desktop
    // it's a real file path, which VideoPlayerController.file handles.
    final controller = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(picked.path))
        : VideoPlayerController.file(File(picked.path));
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();

    setState(() {
      _image = null;
      _imagePreview = null;
      _video = picked;
      _videoController?.dispose();
      _videoController = controller;
    });
  }

  Future<void> _clearVideo() async {
    if (_videoController != null) {
      await _videoController!.dispose();
      _videoController = null;
    }
    _video = null;
  }

  Future<void> _submit() async {
    if (_textController.text.trim().isEmpty) return;

    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await ApiService.instance.createPost(
        text: _textController.text.trim(),
        image: _image,
        video: _video,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sand,
      appBar: AppBar(
        title: const Text('New post'),
        actions: [
          TextButton(
            onPressed: _posting ? null : _submit,
            child: _posting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Post'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.clay)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _textController,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: "What's on your mind?",
                ),
              ),
              const SizedBox(height: 16),
              if (_imagePreview != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    _imagePreview!,
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                )
              else if (_videoController != null &&
                  _videoController!.value.isInitialized)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(_image == null ? 'Add a photo' : 'Change photo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.videocam_outlined),
                      label: Text(_video == null ? 'Add a video' : 'Change video'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
