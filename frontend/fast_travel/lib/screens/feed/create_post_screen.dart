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

enum _MediaTab { photo, video }

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _textController = TextEditingController();
  XFile? _image;
  Uint8List? _imagePreview;
  XFile? _video;
  VideoPlayerController? _videoController;
  bool _posting = false;
  String? _error;
  _MediaTab _tab = _MediaTab.video;

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

  void _clearImage() {
    _image = null;
    _imagePreview = null;
  }

  Future<void> _removeMedia() async {
    await _clearVideo();
    setState(_clearImage);
  }

  void _selectTab(_MediaTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
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

  bool get _hasMedia => _imagePreview != null || _videoController != null;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.ochre,
                    ),
                  )
                : const Text(
                    'Post',
                    style: TextStyle(
                      color: AppColors.ochre,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.clay)),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  _MediaTabButton(
                    label: 'Videos',
                    selected: _tab == _MediaTab.video,
                    onTap: () => _selectTab(_MediaTab.video),
                  ),
                  const SizedBox(width: 28),
                  _MediaTabButton(
                    label: 'Photos',
                    selected: _tab == _MediaTab.photo,
                    onTap: () => _selectTab(_MediaTab.photo),
                  ),
                ],
              ),
              const Divider(height: 1, color: AppColors.sandDim),
              const SizedBox(height: 20),
              _UploadDropzone(
                tab: _tab,
                imagePreview: _imagePreview,
                videoController: _videoController,
                onTap: _tab == _MediaTab.photo ? _pickImage : _pickVideo,
                onRemove: _hasMedia ? _removeMedia : null,
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _InfoTip(
                        width: itemWidth,
                        icon: Icons.straighten_rounded,
                        title: 'Size and duration',
                        subtitle: _tab == _MediaTab.video
                            ? 'Up to 100 MB, 60s max'
                            : 'Up to 20 MB per photo',
                      ),
                      _InfoTip(
                        width: itemWidth,
                        icon: Icons.folder_outlined,
                        title: 'File formats',
                        subtitle: _tab == _MediaTab.video
                            ? '.mp4 recommended'
                            : '.jpg or .png recommended',
                      ),
                      _InfoTip(
                        width: itemWidth,
                        icon: Icons.hd_outlined,
                        title: 'Resolution',
                        subtitle: 'High-res recommended: 1080p+',
                      ),
                      _InfoTip(
                        width: itemWidth,
                        icon: Icons.crop_free_rounded,
                        title: 'Aspect ratio',
                        subtitle: 'Recommended: 4:5 or 1:1',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text('Caption', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: "What's on your mind?",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaTabButton extends StatelessWidget {
  const _MediaTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 3,
              width: 28,
              decoration: BoxDecoration(
                color: selected ? AppColors.ochre : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadDropzone extends StatelessWidget {
  const _UploadDropzone({
    required this.tab,
    required this.imagePreview,
    required this.videoController,
    required this.onTap,
    required this.onRemove,
  });

  final _MediaTab tab;
  final Uint8List? imagePreview;
  final VideoPlayerController? videoController;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  bool get _hasPreview =>
      imagePreview != null ||
      (videoController != null && videoController!.value.isInitialized);

  @override
  Widget build(BuildContext context) {
    final label = tab == _MediaTab.photo ? 'photo' : 'video';
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 280,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.sandDim,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.ink.withValues(alpha: 0.08)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imagePreview != null)
              Image.memory(imagePreview!, fit: BoxFit.cover)
            else if (videoController != null &&
                videoController!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: videoController!.value.size.width,
                  height: videoController!.value.size.height,
                  child: VideoPlayer(videoController!),
                ),
              )
            else
              InkWell(
                onTap: onTap,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.canopy.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                tab == _MediaTab.photo
                                    ? Icons.image_outlined
                                    : Icons.play_arrow_rounded,
                                size: 32,
                                color: AppColors.canopy,
                              ),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: AppColors.ochre,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.sandDim,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 14,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select $label to upload',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        kIsWeb
                            ? 'Or drag and drop it here'
                            : 'Or choose from your gallery',
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.ochre,
                          foregroundColor: AppColors.ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: Text('Select $label'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_hasPreview) ...[
              Positioned(
                top: 12,
                right: 12,
                child: Row(
                  children: [
                    _RoundIconButton(icon: Icons.sync_alt_rounded, onTap: onTap),
                    if (onRemove != null) ...[
                      const SizedBox(width: 8),
                      _RoundIconButton(icon: Icons.close_rounded, onTap: onRemove!),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: AppColors.sand),
      ),
    );
  }
}

class _InfoTip extends StatelessWidget {
  const _InfoTip({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
