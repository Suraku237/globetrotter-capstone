import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// MapLibre (the 3D map) has full support on Android/iOS/Web; desktop
/// support is experimental/absent, so desktop keeps the old flutter_map 2D
/// view. kIsWeb is checked first since dart:io's Platform throws on web.
bool get use3DMap => kIsWeb || Platform.isAndroid || Platform.isIOS;

/// Free, no-API-key vector style with building-extrusion data — paired with
/// CameraPosition(tilt: ...) for the actual 3D perspective.
const String mapStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';
