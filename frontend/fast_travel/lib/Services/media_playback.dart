import 'package:flutter/foundation.dart';

/// The app's call owner suspends feed playback while call audio owns the device.
class MediaPlayback {
  static final suspended = ValueNotifier<bool>(false);
}
