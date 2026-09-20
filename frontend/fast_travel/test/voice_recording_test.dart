import 'dart:async';

import 'package:fast_travel/screens/chat/voice_recording.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

class _Recorder implements AudioRecorder {
  final calls = <String>[];
  final enteredStart = Completer<void>();
  Completer<bool>? permission;
  Completer<void>? starting;
  Completer<void>? pausing;
  Completer<void>? stopping;
  bool permitted = true;
  bool recording = false;
  bool paused = false;
  bool disposed = false;
  Object? startError;
  Object? pauseError;
  Object? resumeError;
  Object? stopError;
  Object? cancelError;
  Object? disposeError;
  String? path;
  int concurrentCalls = 0;
  int maximumConcurrentCalls = 0;

  Future<T> _call<T>(String name, Future<T> Function() body) async {
    calls.add(name);
    concurrentCalls++;
    if (concurrentCalls > maximumConcurrentCalls) {
      maximumConcurrentCalls = concurrentCalls;
    }
    try {
      return await body();
    } finally {
      concurrentCalls--;
    }
  }

  @override
  Future<bool> hasPermission() => _call('permission',
      () async => permission == null ? permitted : await permission!.future);

  @override
  Future<void> start(RecordConfig config, {required String path}) =>
      _call('start', () async {
        expect(config.encoder, AudioEncoder.aacLc);
        this.path = path;
        recording = true;
        if (!enteredStart.isCompleted) enteredStart.complete();
        await starting?.future;
        if (startError != null) throw startError!;
      });

  @override
  Future<void> pause() => _call('pause', () async {
        await pausing?.future;
        if (pauseError != null) throw pauseError!;
        paused = true;
      });

  @override
  Future<void> resume() => _call('resume', () async {
        if (resumeError != null) throw resumeError!;
        paused = false;
      });

  @override
  Future<String?> stop() => _call('stop', () async {
        await stopping?.future;
        if (stopError != null) throw stopError!;
        recording = false;
        paused = false;
        return path;
      });

  @override
  Future<void> cancel() => _call('cancel', () async {
        if (cancelError != null) throw cancelError!;
        recording = false;
        paused = false;
        path = null;
      });

  @override
  Future<void> dispose() => _call('dispose', () async {
        if (disposeError != null) throw disposeError!;
        recording = false;
        paused = false;
        disposed = true;
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Recorder recorder;
  late VoiceRecordingController controller;
  late Duration now;
  var closedInTest = false;

  setUp(() {
    closedInTest = false;
    recorder = _Recorder();
    now = Duration.zero;
    controller = VoiceRecordingController(
      recorderFactory: () => recorder,
      elapsedClock: () => now,
    );
  });

  tearDown(() async {
    if (!closedInTest) await controller.close();
  });

  test('text-only use never constructs or calls the recorder', () async {
    var creations = 0;
    final unused = VoiceRecordingController(recorderFactory: () {
      creations++;
      return recorder;
    });
    await unused.pause();
    await unused.resume();
    expect(await unused.stop(), isNull);
    await unused.cancel();
    await unused.close();
    unused.dispose();
    expect(creations, 0);
    expect(recorder.calls, isEmpty);
  });

  test('elapsed freezes, excludes pauses and survives stop until next start',
      () async {
    await controller.start(path: 'voice.m4a');
    now += const Duration(milliseconds: 1250);
    expect(controller.elapsed, const Duration(milliseconds: 1250));
    await controller.pause();
    expect(controller.active, isTrue);
    expect(controller.paused, isTrue);
    now += const Duration(seconds: 20);
    expect(controller.elapsed, const Duration(milliseconds: 1250));
    await controller.resume();
    now += const Duration(milliseconds: 750);
    expect(controller.elapsed, const Duration(seconds: 2));
    await controller.pause();
    now += const Duration(minutes: 1);
    expect(await controller.stop(), 'voice.m4a');
    expect(controller.elapsed, const Duration(seconds: 2));
    expect(controller.active, isFalse);
    expect(controller.paused, isFalse);
    expect(recorder.calls.where((call) => call == 'start').length, 1);
    now += const Duration(seconds: 30);
    expect(controller.elapsed, const Duration(seconds: 2));
    await controller.start(path: 'next.m4a');
    expect(controller.elapsed, Duration.zero);
    expect(await controller.stop(), 'next.m4a');
  });

  test('permission denial is explicit and never starts a microphone', () async {
    recorder.permitted = false;
    await expectLater(controller.start(path: 'voice.m4a'),
        throwsA(isA<VoiceRecordingPermissionException>()));
    expect(controller.active, isFalse);
    expect(controller.busy, isFalse);
    expect(recorder.calls, ['permission']);
    recorder.permitted = true;
    await controller.start(path: 'voice.m4a');
    expect(controller.active, isTrue);
  });

  test('cancel invalidates a start waiting for permission', () async {
    recorder.permission = Completer<bool>();
    final start = controller.start(path: 'voice.m4a');
    await Future<void>.delayed(Duration.zero);
    final cancel = controller.cancel();
    var cancelled = false;
    cancel.then((_) => cancelled = true);
    expect(controller.busy, isTrue);
    expect(cancelled, isFalse);
    recorder.permission!.complete(true);
    await Future.wait([start, cancel]);
    expect(recorder.calls, ['permission']);
    expect(controller.active, isFalse);
    expect(controller.busy, isFalse);
  });

  test('close invalidates pending permission and rejects new starts', () async {
    recorder.permission = Completer<bool>();
    final start = controller.start(path: 'voice.m4a');
    await Future<void>.delayed(Duration.zero);
    final close = controller.close();
    expect(identical(close, controller.close()), isTrue);
    await expectLater(controller.start(path: 'late.m4a'), throwsStateError);
    recorder.permission!.complete(true);
    await Future.wait([start, close]);
    expect(recorder.calls, ['permission', 'dispose']);
    expect(recorder.recording, isFalse);
    expect(controller.busy, isFalse);
  });

  test(
      'dispose waits for a native start before releasing and never notifies late',
      () async {
    recorder.starting = Completer<void>();
    var notifications = 0;
    controller.addListener(() => notifications++);
    final start = controller.start(path: 'voice.m4a');
    await recorder.enteredStart.future;
    controller.dispose();
    final atDispose = notifications;
    expect(recorder.disposed, isFalse);
    recorder.starting!.complete();
    await start;
    await controller.close();
    expect(recorder.calls, ['permission', 'start', 'cancel', 'dispose']);
    expect(recorder.recording, isFalse);
    expect(controller.active, isFalse);
    expect(notifications, atDispose);
    expect(recorder.maximumConcurrentCalls, 1);
  });

  for (final discard in [false, true]) {
    test('${discard ? 'cancel' : 'stop'} awaits a pending native start',
        () async {
      recorder.starting = Completer<void>();
      final start = controller.start(path: 'voice.m4a');
      await recorder.enteredStart.future;
      final release = discard
          ? controller.cancel().then<String?>((_) => null)
          : controller.stop();
      expect(recorder.recording, isTrue);
      expect(recorder.calls, ['permission', 'start']);
      recorder.starting!.complete();
      await start;
      expect(await release, discard ? isNull : 'voice.m4a');
      expect(recorder.recording, isFalse);
      expect(controller.active, isFalse);
      expect(controller.busy, isFalse);
      expect(recorder.maximumConcurrentCalls, 1);
    });
  }

  test('rapid start, pause, resume and stop actions serialize and deduplicate',
      () async {
    await controller.start(path: 'voice.m4a');
    recorder.pausing = Completer<void>();
    final duplicateStart = controller.start(path: 'duplicate.m4a');
    final pause = controller.pause();
    final duplicatePause = controller.pause();
    final resume = controller.resume();
    final duplicateResume = controller.resume();
    final stop = controller.stop();
    final lateResume = controller.resume();
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);
    expect(recorder.calls.last, 'pause');
    recorder.pausing!.complete();
    await Future.wait([
      duplicateStart,
      pause,
      duplicatePause,
      resume,
      duplicateResume,
      stop,
      lateResume,
    ]);
    expect(recorder.calls, ['permission', 'start', 'pause', 'resume', 'stop']);
    expect(recorder.maximumConcurrentCalls, 1);
    expect(controller.active, isFalse);
    expect(recorder.recording, isFalse);
    expect(controller.busy, isFalse);
  });

  test('failed pause and resume preserve the last confirmed state and timing',
      () async {
    final failure = PlatformException(code: 'control-failed');
    await controller.start(path: 'voice.m4a');
    recorder.pauseError = failure;
    await expectLater(
        controller.pause(),
        throwsA(isA<VoiceRecordingException>()
            .having((e) => e.cause, 'cause', failure)));
    now += const Duration(seconds: 2);
    expect(controller.paused, isFalse);
    expect(controller.elapsed, const Duration(seconds: 2));
    expect(controller.busy, isFalse);
    recorder.pauseError = null;
    await controller.pause();
    recorder.resumeError = failure;
    await expectLater(
        controller.resume(), throwsA(isA<VoiceRecordingException>()));
    now += const Duration(seconds: 5);
    expect(controller.active, isTrue);
    expect(controller.paused, isTrue);
    expect(controller.elapsed, const Duration(seconds: 2));
    recorder.resumeError = null;
    await controller.resume();
    now += const Duration(seconds: 1);
    expect(controller.elapsed, const Duration(seconds: 3));
    await controller.cancel();
    expect(recorder.recording, isFalse);
  });

  test('a partially failed native start is cancelled and its error is surfaced',
      () async {
    recorder.startError = StateError('started before failing');
    await expectLater(
        controller.start(path: 'voice.m4a'),
        throwsA(isA<VoiceRecordingException>()
            .having((e) => e.operation, 'operation', 'start')));
    expect(recorder.calls, ['permission', 'start', 'cancel']);
    expect(recorder.recording, isFalse);
    expect(controller.active, isFalse);
    recorder.startError = null;
    await controller.start(path: 'retry.m4a');
    expect(controller.active, isTrue);
  });

  test('a failed stop still releases the microphone and surfaces the failure',
      () async {
    await controller.start(path: 'voice.m4a');
    recorder.stopError = StateError('stop failed');
    await expectLater(
        controller.stop(), throwsA(isA<VoiceRecordingException>()));
    expect(recorder.calls, ['permission', 'start', 'stop', 'cancel']);
    expect(recorder.recording, isFalse);
    expect(controller.active, isFalse);
    expect(controller.busy, isFalse);
  });

  test('failed cancel and stop still dispose and expose all release errors',
      () async {
    await controller.start(path: 'voice.m4a');
    recorder.cancelError = StateError('cancel failed');
    recorder.stopError = StateError('stop failed');
    await expectLater(
      controller.cancel(),
      throwsA(isA<VoiceRecordingException>()
          .having((e) => e.cause, 'cause', recorder.cancelError)
          .having(
              (e) => e.cleanupErrors, 'cleanup errors', [recorder.stopError])),
    );
    expect(
        recorder.calls, ['permission', 'start', 'cancel', 'stop', 'dispose']);
    expect(recorder.recording, isFalse);
    expect(controller.active, isFalse);
    expect(controller.busy, isFalse);
    expect(recorder.disposed, isTrue);
  });

  test(
      'failed startup with failed cleanup stays releasable and reports every error',
      () async {
    recorder.startError = StateError('start failed');
    recorder.cancelError = StateError('cancel failed');
    recorder.stopError = StateError('stop failed');
    recorder.disposeError = StateError('dispose failed');
    await expectLater(
      controller.start(path: 'voice.m4a'),
      throwsA(isA<VoiceRecordingException>()
          .having((e) => e.cause, 'cause', recorder.startError)
          .having((e) => e.cleanupErrors, 'cleanup errors', [
        recorder.cancelError,
        recorder.stopError,
        recorder.disposeError
      ])),
    );
    expect(controller.active, isTrue);
    expect(controller.busy, isFalse);
    expect(recorder.recording, isTrue);
    recorder.cancelError = null;
    recorder.disposeError = null;
    await controller.cancel();
    expect(controller.active, isFalse);
    expect(recorder.recording, isFalse);
  });

  testWidgets('timer rebuilds during recording and stays frozen while paused',
      (tester) async {
    try {
      await controller.start(path: 'voice.m4a');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: VoiceRecordingBar(
        controller: controller,
        onSend: () {},
        onCancel: () {},
        onPauseResume: () {},
      ))));
      now += const Duration(seconds: 3);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('00:03'), findsOneWidget);
      await controller.pause();
      await tester.pump();
      now += const Duration(seconds: 15);
      await tester.pump(const Duration(seconds: 15));
      expect(find.text('00:03'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byTooltip('Resume recording'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.close();
      closedInTest = true;
    }
  });

  for (final locale in ['en', 'fr']) {
    testWidgets('recording controls fit 240px at 2x text in $locale',
        (tester) async {
      try {
        await controller.start(path: 'voice.m4a');
        var sends = 0;
        var cancels = 0;
        var pauses = 0;
        await tester.pumpWidget(MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SizedBox(
                  width: 240,
                  child: VoiceRecordingBar(
                    controller: controller,
                    onSend: () => sends++,
                    onCancel: () => cancels++,
                    onPauseResume: () => pauses++,
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final pause = locale == 'fr'
            ? "Mettre l'enregistrement en pause"
            : 'Pause recording';
        final resume =
            locale == 'fr' ? "Reprendre l'enregistrement" : 'Resume recording';
        final cancel =
            locale == 'fr' ? "Annuler l'enregistrement" : 'Cancel recording';
        final send = locale == 'fr' ? 'Arrêter et envoyer' : 'Stop and send';
        expect(find.text(pause), findsOneWidget);
        await tester.tap(find.byTooltip(pause));
        await tester.tap(find.byTooltip(cancel));
        await tester.tap(find.byTooltip(send));
        expect([pauses, cancels, sends], [1, 1, 1]);
        await controller.pause();
        await tester.pumpAndSettle();
        expect(find.text(resume), findsOneWidget);
        expect(tester.takeException(), isNull);
        recorder.stopping = Completer<void>();
        final stopping = controller.stop();
        await tester.pump();
        expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed,
            isNull);
        expect(
            tester
                .widget<IconButton>(
                    find.widgetWithIcon(IconButton, Icons.send_rounded))
                .onPressed,
            isNull);
        recorder.stopping!.complete();
        await stopping;
      } finally {
        final stopping = recorder.stopping;
        if (stopping != null && !stopping.isCompleted) stopping.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.close();
        closedInTest = true;
      }
    });
  }
}
