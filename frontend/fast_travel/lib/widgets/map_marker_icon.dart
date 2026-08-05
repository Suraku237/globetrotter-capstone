import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// MapLibre's symbols are image-based (unlike flutter_map's Marker, which
/// accepts any Flutter widget) — this draws a simple pin shape straight to a
/// PNG at runtime via dart:ui, so no bundled icon asset is needed.
Future<Uint8List> buildPinMarkerBytes({
  required Color color,
  double size = 80,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = color;
  final center = Offset(size / 2, size * 0.38);
  final radius = size * 0.32;

  final path = Path()
    ..addOval(Rect.fromCircle(center: center, radius: radius))
    ..moveTo(center.dx - radius * 0.55, center.dy + radius * 0.7)
    ..lineTo(center.dx, size * 0.96)
    ..lineTo(center.dx + radius * 0.55, center.dy + radius * 0.7)
    ..close();
  canvas.drawPath(path, paint);
  canvas.drawCircle(center, radius * 0.42, Paint()..color = Colors.white);

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
