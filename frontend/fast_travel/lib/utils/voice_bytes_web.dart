import 'dart:typed_data';

import 'package:http/http.dart' as http;

// Web path: `record` returns a blob: URL — package:http can GET it and
// resolve straight to bytes, so no dart:html direct dependency is needed.
Future<Uint8List> readVoiceBytes(String pathOrUrl) async {
  final response = await http.get(Uri.parse(pathOrUrl));
  return response.bodyBytes;
}
