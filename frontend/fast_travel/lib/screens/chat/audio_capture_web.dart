// Web side of the conditional import in chat_thread_screen.dart. dart:io
// doesn't exist on web at all (importing it is a compile error there, not
// just a runtime one) — so this stub keeps the same function signatures
// without ever touching it. Web reads the recorded audio via its blob URL
// over HTTP instead (see chat_thread_screen.dart's kIsWeb branch), so
// readAudioBytes here is never actually called — audioTempPath's return
// value isn't used as a real path on web either (package:record manages
// the capture location itself there).
import 'dart:typed_data';

String audioTempPath(String filename) => filename;

Future<Uint8List> readAudioBytes(String path) async {
  throw UnsupportedError('Not available on web — read the blob URL instead.');
}
