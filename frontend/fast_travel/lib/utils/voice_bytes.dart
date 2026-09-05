// Cross-platform reader for the recorded voice file the `record` plugin
// hands back.
//
// The plugin returns:
//   * on native: a filesystem path (e.g. .../voice_1725530000.m4a)
//   * on web:    a blob: URL that can only be read through the browser
//
// The concrete implementations live in the two sibling files; this file
// picks whichever one matches the current platform at compile time so
// neither `dart:io` nor a blob-fetch is pulled into the other bundle.
export 'voice_bytes_stub.dart'
    if (dart.library.io) 'voice_bytes_io.dart'
    if (dart.library.html) 'voice_bytes_web.dart';
