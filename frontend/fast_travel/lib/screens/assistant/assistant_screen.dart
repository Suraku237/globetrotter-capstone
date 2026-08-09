import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../Services/api_service.dart';
import '../../theme/app_theme.dart';

class _ChatMessage {
  final String text;
  final bool fromUser;
  _ChatMessage(this.text, this.fromUser);
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechAvailable = false;
  bool _listening = false;
  bool _sending = false;
  bool _speakReplies = true;
  String _liveTranscript = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _messages.add(_ChatMessage(
      "Hi! I'm your Fast Travel assistant — ask me anything about "
      "destinations, itineraries, or planning a trip in Cameroon.",
      false,
    ));
    _loadHistory();
  }

  // The backend already remembers this user's past conversation for
  // context — this just makes that visible on screen too, instead of
  // always starting from a blank chat.
  Future<void> _loadHistory() async {
    try {
      final history = await ApiService.instance.getAssistantHistory();
      if (!mounted || history.isEmpty) return;
      setState(() {
        _messages.addAll(history.map((turn) => _ChatMessage(
              turn['text'] as String,
              turn['role'] == 'user',
            )));
      });
      _scrollToBottom();
    } catch (_) {
      // Non-critical — the chat just starts fresh if history can't load.
    }
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (error) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      if (_liveTranscript.trim().isNotEmpty) {
        _send(_liveTranscript.trim());
      }
      _liveTranscript = '';
      return;
    }

    if (!_speechAvailable) return;

    setState(() {
      _listening = true;
      _liveTranscript = '';
    });
    await _speech.listen(
      onResult: (result) {
        setState(() => _liveTranscript = result.recognizedWords);
        if (result.finalResult) {
          _speech.stop();
          setState(() => _listening = false);
          if (result.recognizedWords.trim().isNotEmpty) {
            _send(result.recognizedWords.trim());
          }
          _liveTranscript = '';
        }
      },
    );
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(text, true));
      _sending = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      final reply = await ApiService.instance.askAssistant(message: text);
      setState(() => _messages.add(_ChatMessage(reply, false)));
      if (_speakReplies) {
        await _tts.speak(reply);
      }
    } on ApiException catch (e) {
      setState(() => _messages.add(_ChatMessage("Couldn't reach the assistant: ${e.message}", false)));
    } catch (_) {
      setState(() => _messages
          .add(_ChatMessage("Couldn't reach the assistant. Check your connection.", false)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sand,
      appBar: AppBar(
        title: const Text('Travel Assistant'),
        actions: [
          IconButton(
            tooltip: _speakReplies ? 'Mute spoken replies' : 'Unmute spoken replies',
            icon: Icon(_speakReplies ? Icons.volume_up_rounded : Icons.volume_off_rounded),
            onPressed: () => setState(() => _speakReplies = !_speakReplies),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final message = _messages[index];
                  return Align(
                    alignment: message.fromUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: message.fromUser
                            ? AppColors.canopy
                            : AppColors.sandDim,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        message.text,
                        style: TextStyle(
                          color: message.fromUser ? AppColors.sand : AppColors.ink,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_listening)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _liveTranscript.isEmpty ? 'Listening…' : _liveTranscript,
                  style: const TextStyle(
                      color: AppColors.inkSoft, fontStyle: FontStyle.italic),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (_speechAvailable)
                    IconButton(
                      tooltip: _listening ? 'Stop' : 'Speak your question',
                      icon: Icon(
                        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _listening ? AppColors.clay : AppColors.ochre,
                      ),
                      onPressed: _toggleListening,
                    ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Ask about a destination or trip...',
                      ),
                      onSubmitted: _send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: AppColors.ochre),
                    onPressed: _sending ? null : () => _send(_textController.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
