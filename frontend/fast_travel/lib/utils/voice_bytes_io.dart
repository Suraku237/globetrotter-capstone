import 'dart:io';
import 'dart:typed_data';

// Native path: `record` writes the audio to a local file and hands back
// the path — just read those bytes off disk.
Future<Uint8List> readVoiceBytes(String pathOrUrl) {
  return File(pathOrUrl).readAsBytes();
}
