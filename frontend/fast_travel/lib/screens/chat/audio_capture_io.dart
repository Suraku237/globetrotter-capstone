// Native (mobile/desktop) side of the conditional import in
// chat_thread_screen.dart — safe to touch dart:io here since this file is
// only ever selected on platforms where dart:io exists.
import 'dart:io';
import 'dart:typed_data';

String audioTempPath(String filename) =>
    '${Directory.systemTemp.path}/$filename';

Future<Uint8List> readAudioBytes(String path) => File(path).readAsBytes();
