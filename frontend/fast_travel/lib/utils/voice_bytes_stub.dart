import 'dart:typed_data';

// Fallback picked only when neither dart:io nor dart:html is available —
// shouldn't be reachable in a real Flutter build, but keeps the
// conditional export self-contained.
Future<Uint8List> readVoiceBytes(String pathOrUrl) {
  throw UnsupportedError(
    'Voice recording bytes are not available on this platform.',
  );
}
