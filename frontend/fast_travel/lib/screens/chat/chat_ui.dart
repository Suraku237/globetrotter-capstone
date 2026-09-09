import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

abstract final class ChatColors {
  static const header = AppColors.ochre;
  static const background = Colors.transparent;
  static const outgoing = Color(0xFFFFE9E2);
  static const ink = AppColors.ink;
  static const muted = AppColors.inkSoft;
}

String chatLabel(BuildContext context, String english, String french) =>
    Localizations.localeOf(context).languageCode == 'fr' ? french : english;

String? chatDay(String timestamp) {
  final date = DateTime.tryParse(timestamp)?.toLocal();
  return date == null ? null : '${date.year}-${date.month}-${date.day}';
}

bool startsChatDay(String? previous, String current) =>
    chatDay(current) != null &&
    (previous == null || chatDay(previous) != chatDay(current));

bool sameChatRun(String firstTime, String nextTime) {
  final first = DateTime.tryParse(firstTime);
  final next = DateTime.tryParse(nextTime);
  return first != null &&
      next != null &&
      chatDay(firstTime) == chatDay(nextTime) &&
      next.difference(first).inSeconds.abs() < 300;
}

List<T> mergeChatMessages<T>(
  Iterable<T> current,
  Iterable<T> incoming, {
  required String Function(T) id,
  required String Function(T) createdAt,
}) {
  final byId = <String, T>{};
  for (final message in [...current, ...incoming]) {
    byId[id(message)] = message;
  }
  final result = byId.values.toList();
  final insertionOrder = {for (var i = 0; i < result.length; i++) id(result[i]): i};
  result.sort((a, b) {
    final first = DateTime.tryParse(createdAt(a));
    final second = DateTime.tryParse(createdAt(b));
    final order = first != null && second != null
        ? first.compareTo(second)
        : createdAt(a).compareTo(createdAt(b));
    return order == 0 ? insertionOrder[id(a)]!.compareTo(insertionOrder[id(b)]!) : order;
  });
  return result;
}

/// Coalesces cached re-reads and pauses network work while the view is hidden.
class ChatRefreshController with WidgetsBindingObserver {
  ChatRefreshController({
    required this.changes,
    required this.topics,
    required this.isLive,
    required this.isVisible,
    required this.load,
    required this.invalidate,
    this.onResume,
  });

  final Stream<Set<String>> changes;
  final Set<String> topics;
  final bool Function() isLive;
  final bool Function() isVisible;
  final Future<void> Function() load;
  final void Function(Set<String>) invalidate;
  final VoidCallback? onResume;
  StreamSubscription<Set<String>>? _subscription;
  Timer? _fallback;
  Completer<void>? _pending;
  bool _queued = false;
  bool _disposed = false;
  bool _foreground = true;
  bool? _wasVisible;

  bool get active => !_disposed && _foreground && isVisible();

  void visibilityChanged() {
    final visible = active;
    if (visible && _wasVisible == false) {
      onResume?.call();
      unawaited(refreshFromNetwork());
    }
    _wasVisible = visible;
  }

  void start() {
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _subscription = changes.listen((changed) {
      if (active &&
          (changed.contains('all') ||
              changed.intersection(topics).isNotEmpty)) {
        unawaited(refresh());
      }
    });
    _startFallback();
    unawaited(refresh());
  }

  void _startFallback() {
    _fallback?.cancel();
    if (!_foreground || _disposed) return;
    _fallback = Timer.periodic(const Duration(seconds: 30), (_) {
      if (active && !isLive()) unawaited(refreshFromNetwork());
    });
  }

  Future<void> refreshFromNetwork() {
    if (_disposed) return Future.value();
    invalidate(topics);
    return refresh();
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final pending = _pending;
    if (pending != null) {
      _queued = true;
      return pending.future;
    }
    final completion = Completer<void>();
    _pending = completion;
    unawaited(_drain(completion));
    return completion.future;
  }

  Future<void> _drain(Completer<void> completion) async {
    try {
      do {
        _queued = false;
        await load();
      } while (_queued && active);
      completion.complete();
    } catch (error, stack) {
      completion.completeError(error, stack);
    } finally {
      _pending = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _fallback?.cancel();
    _startFallback();
    if (active) {
      onResume?.call();
      unawaited(refreshFromNetwork());
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _fallback?.cancel();
    unawaited(_subscription?.cancel());
  }
}

class ChatDateSeparator extends StatelessWidget {
  const ChatDateSeparator({super.key, required this.timestamp});
  final String timestamp;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(timestamp)?.toLocal();
    if (date == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final label = day == today
        ? chatLabel(context, 'Today', "Aujourd'hui")
        : day == yesterday
            ? chatLabel(context, 'Yesterday', 'Hier')
            : MaterialLocalizations.of(context).formatMediumDate(date);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.sand.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(
                color: ChatColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class ChatNotice extends StatelessWidget {
  const ChatNotice({
    super.key,
    required this.message,
    this.onRetry,
    this.onDismiss,
    this.actionLabel,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFFFF4DD),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: ChatColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(message,
                      style:
                          const TextStyle(color: ChatColors.ink, fontSize: 12)),
                ),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(actionLabel ??
                      chatLabel(context, 'Retry', 'Réessayer')),
                ),
              if (onDismiss != null)
                IconButton(
                  tooltip: chatLabel(context, 'Dismiss', 'Fermer'),
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
        ),
      );
}

Future<bool> confirmChatRetry(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(chatLabel(context, 'Send again?', 'Renvoyer le message ?')),
        content: Text(chatLabel(
          context,
          'The previous send was not confirmed. Check the chat first: retrying may send the message twice.',
          "L'envoi précédent n'a pas été confirmé. Vérifiez la discussion : réessayer peut envoyer le message deux fois.",
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(chatLabel(context, 'Cancel', 'Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(chatLabel(context, 'Send again', 'Renvoyer')),
          ),
        ],
      ),
    ) ??
    false;
