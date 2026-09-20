import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'chat_ui.dart';

class VoiceRecordingPermissionException implements Exception {
  const VoiceRecordingPermissionException();

  @override
  String toString() => 'Microphone permission is required.';
}

class VoiceRecordingException implements Exception {
  VoiceRecordingException(
    this.operation,
    this.cause, {
    Iterable<Object> cleanupErrors = const [],
  }) : cleanupErrors = List.unmodifiable(cleanupErrors);

  final String operation;
  final Object cause;
  final List<Object> cleanupErrors;

  @override
  String toString() => 'Voice recording $operation failed: $cause'
      '${cleanupErrors.isEmpty ? '' : ' (cleanup: ${cleanupErrors.join('; ')})'}';
}

/// Owns one recording, including pauses, until it is sent or discarded.
///
/// Operations are serialized. A stop/cancel also invalidates starts still
/// waiting for permission. Such interrupted starts complete without recording.
/// [elapsedClock], when supplied for tests, must be a monotonic clock.
///
/// Await [close] when microphone release must complete before proceeding.
/// [dispose] starts the same cleanup and reports asynchronous errors through
/// FlutterError; either method also disposes the ChangeNotifier.
class VoiceRecordingController extends ChangeNotifier {
  VoiceRecordingController({
    AudioRecorder Function()? recorderFactory,
    Duration Function()? elapsedClock,
  })  : _recorderFactory = recorderFactory ?? AudioRecorder.new,
        _elapsedClock = elapsedClock;

  final AudioRecorder Function() _recorderFactory;
  final Duration Function()? _elapsedClock;
  final Stopwatch _clock = Stopwatch()..start();
  AudioRecorder? _recorder;
  Future<void>? _tail;
  Future<void>? _closeFuture;
  Timer? _ticker;
  Duration _accumulated = Duration.zero;
  Duration? _runningSince;
  int _pending = 0;
  int _generation = 0;
  bool _active = false;
  bool _paused = false;
  bool _needsRelease = false;
  bool _closing = false;
  bool _notifierDisposed = false;

  bool get active => _active;
  bool get paused => _paused;
  bool get busy => _pending > 0;
  Duration get _now => _elapsedClock?.call() ?? _clock.elapsed;
  Duration get elapsed =>
      _accumulated +
      (_runningSince == null ? Duration.zero : _now - _runningSince!);

  Future<void> start({required String path}) {
    if (_closing) return Future.error(StateError('Voice recorder is closed.'));
    final generation = _generation;
    return _enqueue(() async {
      if (_closing || generation != _generation || _active) return;
      if (_needsRelease) {
        throw StateError('The previous recording has not been released.');
      }
      try {
        final recorder = _recorder ??= _recorderFactory();
        final permitted = await recorder.hasPermission();
        if (_closing || generation != _generation) return;
        if (!permitted) throw const VoiceRecordingPermissionException();
        // A native start can acquire the microphone before its Future resolves.
        _needsRelease = true;
        await recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        _accumulated = Duration.zero;
        _active = true;
        _paused = false;
        _runClock();
      } on VoiceRecordingPermissionException {
        rethrow;
      } catch (error, stack) {
        final cleanupErrors = await _discardRecorder();
        Error.throwWithStackTrace(
          VoiceRecordingException('start', error, cleanupErrors: cleanupErrors),
          stack,
        );
      }
    });
  }

  Future<void> pause() {
    if (_closing) return Future.error(StateError('Voice recorder is closed.'));
    return _enqueue(() async {
      if (!_active || _paused || _closing) return;
      try {
        await _recorder!.pause();
        _freezeClock();
        _paused = true;
      } catch (error, stack) {
        Error.throwWithStackTrace(
            VoiceRecordingException('pause', error), stack);
      }
    });
  }

  Future<void> resume() {
    if (_closing) return Future.error(StateError('Voice recorder is closed.'));
    return _enqueue(() async {
      if (!_active || !_paused || _closing) return;
      try {
        await _recorder!.resume();
        _paused = false;
        _runClock();
      } catch (error, stack) {
        Error.throwWithStackTrace(
            VoiceRecordingException('resume', error), stack);
      }
    });
  }

  Future<String?> stop() {
    if (_closing) return _closeFuture!.then((_) => null);
    _generation++;
    return _enqueue(() async {
      if (!_needsRelease) return null;
      try {
        final path = await _recorder!.stop();
        _finishRecording();
        return path;
      } catch (error, stack) {
        final cleanupErrors = await _discardRecorder();
        Error.throwWithStackTrace(
          VoiceRecordingException('stop', error, cleanupErrors: cleanupErrors),
          stack,
        );
      }
    });
  }

  Future<void> cancel() {
    if (_closing) return _closeFuture!;
    _generation++;
    return _enqueue(() async {
      final errors = await _discardRecorder();
      _throwCleanupErrors('cancel', errors);
    });
  }

  Future<void> close() {
    final closing = _closeFuture;
    if (closing != null) return closing;
    _closing = true;
    _generation++;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    _enqueue(() async {
      try {
        final errors = await _discardRecorder(disposeRecorder: true);
        _throwCleanupErrors('close', errors);
      } finally {
        if (!_notifierDisposed) {
          _ticker?.cancel();
          _notifierDisposed = true;
          super.dispose();
        }
      }
    }).then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    _pending++;
    final result = (_tail ?? Future<void>.value()).then((_) async {
      try {
        return await operation();
      } finally {
        _pending--;
        _notify();
      }
    });
    // Only the queue's branch handles errors; the caller's Future still fails.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _notify();
    return result;
  }

  Future<List<Object>> _discardRecorder({bool disposeRecorder = false}) async {
    final recorder = _recorder;
    if (recorder == null) return [];
    final errors = <Object>[];
    if (_needsRelease) {
      try {
        await recorder.cancel();
        _finishRecording();
      } catch (error) {
        errors.add(error);
        disposeRecorder = true;
        // Even a failed cancel must not prevent another release attempt.
        try {
          await recorder.stop();
          _finishRecording();
        } catch (error) {
          errors.add(error);
        }
      }
    }
    if (disposeRecorder) {
      try {
        await recorder.dispose();
        _finishRecording();
        _recorder = null;
      } catch (error) {
        errors.add(error);
      }
    }
    // A partially failed start may still own the mic. Keep release controls
    // available if every native cleanup attempt failed.
    if (_needsRelease) _active = true;
    return errors;
  }

  void _throwCleanupErrors(String operation, List<Object> errors) {
    if (errors.isNotEmpty) {
      throw VoiceRecordingException(
        operation,
        errors.first,
        cleanupErrors: errors.skip(1),
      );
    }
  }

  void _runClock() {
    _runningSince = _now;
    _ticker?.cancel();
    if (!_notifierDisposed && !_closing) {
      _ticker =
          Timer.periodic(const Duration(milliseconds: 200), (_) => _notify());
    }
  }

  void _freezeClock() {
    _accumulated = elapsed;
    _runningSince = null;
    _ticker?.cancel();
    _ticker = null;
  }

  void _finishRecording() {
    _freezeClock();
    _active = false;
    _paused = false;
    _needsRelease = false;
  }

  void _notify() {
    if (!_notifierDisposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_notifierDisposed) return;
    _ticker?.cancel();
    _notifierDisposed = true;
    super.dispose();
    unawaited(close().catchError((Object error, StackTrace stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'voice recording',
        context: ErrorDescription('while releasing the microphone'),
      ));
    }));
  }
}

class VoiceRecordingBar extends StatelessWidget {
  const VoiceRecordingBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onCancel,
    required this.onPauseResume,
  });

  final VoiceRecordingController controller;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onPauseResume;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final paused = controller.paused;
          final enabled = controller.active && !controller.busy;
          final pauseLabel = paused
              ? chatLabel(
                  context, 'Resume recording', "Reprendre l'enregistrement")
              : chatLabel(context, 'Pause recording',
                  "Mettre l'enregistrement en pause");
          final status = controller.active
              ? paused
                  ? chatLabel(context, 'Paused', 'En pause')
                  : chatLabel(context, 'Recording', 'Enregistrement')
              : controller.busy
                  ? chatLabel(context, 'Preparing recording',
                      "Préparation de l'enregistrement")
                  : chatLabel(
                      context, 'Recording stopped', 'Enregistrement arrêté');
          final seconds = controller.elapsed.inSeconds;
          final duration =
              '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  children: [
                    Icon(
                      paused
                          ? Icons.pause_circle_outline
                          : Icons.fiber_manual_record,
                      size: 16,
                      color: controller.active && !paused
                          ? Colors.redAccent
                          : ChatColors.muted,
                    ),
                    Text(status, textAlign: TextAlign.center),
                    Text(duration,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    IconButton(
                      tooltip: chatLabel(context, 'Cancel recording',
                          "Annuler l'enregistrement"),
                      onPressed: enabled ? onCancel : null,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                    Tooltip(
                      message: pauseLabel,
                      child: TextButton(
                        onPressed: enabled ? onPauseResume : null,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(paused
                                ? Icons.mic_rounded
                                : Icons.pause_rounded),
                            Text(pauseLabel, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: chatLabel(
                          context, 'Stop and send', 'Arrêter et envoyer'),
                      onPressed: enabled ? onSend : null,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}
