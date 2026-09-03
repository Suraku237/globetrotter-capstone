import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../Services/api_service.dart';
import '../../theme/app_theme.dart';

class _ChatMessage {
  final String text;
  final bool fromUser;
  const _ChatMessage(this.text, this.fromUser);
}

class AssistantScreen extends StatefulWidget {
  // Set when opened from a specific context (e.g. a destination's "Ask the
  // assistant" row) — sent automatically once history loads, only if that
  // history is empty, so reopening the chat later never re-asks it.
  final String? initialQuestion;

  const AssistantScreen({super.key, this.initialQuestion});

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
  bool _loadingHistory = true;
  String _liveTranscript = '';

  static const _greeting = _ChatMessage(
    "Hi! I'm your Fast Travel assistant — ask me anything about "
    "destinations, itineraries, or planning a trip in Cameroon.",
    false,
  );

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadHistory();
  }

  // The backend remembers this user's conversation permanently (tied to
  // their account, not this browser/app session) — this loads the real
  // history before showing anything, rather than always starting blank
  // and only silently gaining memory in the background.
  Future<void> _loadHistory() async {
    try {
      final history = await ApiService.instance.getAssistantHistory();
      if (!mounted) return;
      final wasEmpty = history.isEmpty;
      setState(() {
        if (wasEmpty) {
          _messages.add(_greeting);
        } else {
          _messages.addAll(history.map((turn) => _ChatMessage(
                turn['text'] as String,
                turn['role'] == 'user',
              )));
        }
        _loadingHistory = false;
      });
      _scrollToBottom();
      if (wasEmpty && widget.initialQuestion != null) {
        _send(widget.initialQuestion!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(_greeting);
        _messages.add(const _ChatMessage(
          "Couldn't load your earlier conversation — nothing was lost, "
          "it's still saved. Check your connection and reopen this screen "
          "to see it again.",
          false,
        ));
        _loadingHistory = false;
      });
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

    // Push the user bubble immediately, plus a placeholder assistant
    // bubble we'll append tokens into as the stream ticks. This is what
    // makes the UI feel instant — the user never sits on a spinner
    // waiting for the full reply to arrive.
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _messages.add(const _ChatMessage('', false));
      _sending = true;
    });
    _textController.clear();
    _scrollToBottom();

    final assistantIndex = _messages.length - 1;
    final buffer = StringBuffer();
    try {
      await for (final delta
          in ApiService.instance.streamAssistant(message: text)) {
        if (!mounted) return;
        buffer.write(delta);
        setState(() {
          _messages[assistantIndex] = _ChatMessage(buffer.toString(), false);
        });
        _scrollToBottom();
      }
      // Speak the whole reply once — piecemeal TTS on every delta
      // stutters badly and reads punctuation out loud.
      if (_speakReplies && buffer.isNotEmpty) {
        await _tts.speak(buffer.toString());
      }
    } on ApiException catch (e) {
      // The stream reported an error mid-flight (rate limit, safety
      // block, upstream fault…). Replace the placeholder with a
      // targeted message rather than leaving an empty bubble.
      if (!mounted) return;
      final friendly = e.statusCode == 429
          ? "The assistant is busy — try again in a moment."
          : e.statusCode == 400
              ? "I couldn't answer that. Try rephrasing your question."
              : e.statusCode == 503
                  ? "The assistant isn't available: ${e.message}"
                  : "Couldn't reach the assistant: ${e.message}";
      setState(() {
        _messages[assistantIndex] = _ChatMessage(friendly, false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages[assistantIndex] = const _ChatMessage(
          "Couldn't reach the assistant. Check your connection.",
          false,
        );
      });
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Travel Assistant'),
        actions: [
          IconButton(
            tooltip:
                _speakReplies ? 'Mute spoken replies' : 'Unmute spoken replies',
            icon: Icon(_speakReplies
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded),
            onPressed: () => setState(() => _speakReplies = !_speakReplies),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loadingHistory)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else
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
                            color: message.fromUser
                                ? AppColors.sand
                                : AppColors.ink,
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
                    icon:
                        const Icon(Icons.send_rounded, color: AppColors.ochre),
                    onPressed:
                        _sending ? null : () => _send(_textController.text),
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
