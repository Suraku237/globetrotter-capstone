import 'package:flutter/material.dart';
import '../../Services/api_service.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

class PostCommentsScreen extends StatefulWidget {
  final Post post;
  const PostCommentsScreen({super.key, required this.post});

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  late Post _post;
  final _commentController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final updated = await ApiService.instance.addComment(_post.id, text);
      setState(() {
        _post = updated;
        _commentController.clear();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sand,
      appBar: AppBar(title: Text('${_post.authorName}\'s post')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_post.text,
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _post.comments.isEmpty
                  ? const Center(child: Text('No comments yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _post.comments.length,
                      itemBuilder: (context, index) {
                        final comment = _post.comments[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(comment.authorName,
                                  style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 2),
                              Text(comment.text),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: const TextStyle(color: AppColors.clay)),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        decoration: const InputDecoration(
                          hintText: 'Add a comment...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _sending
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send_rounded,
                                color: AppColors.ochre),
                            onPressed: _addComment,
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
