import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'preference_storage.dart';

/// Device-level preference: signing out must not re-enable automatic downloads.
class MediaSettings extends ChangeNotifier {
  static final instance = MediaSettings();
  static const preferenceKey = 'media_data_saver';

  bool _dataSaver = true;
  bool get dataSaver => _dataSaver;
  Future<void>? _loading;
  Future<void>? _writes;
  bool _loaded = false;
  String? storageError;

  Future<void> load() => _loaded ? Future.value() : (_loading ??= _load());

  Future<void> _load() async {
    try {
      final prefs = await preferenceStorage(SharedPreferences.getInstance);
      _dataSaver = prefs.getBool(preferenceKey) ?? true;
      storageError = null;
    } on PreferenceStorageException catch (error) {
      storageError = error.toString();
    } finally {
      _loaded = true;
      _loading = null;
      notifyListeners();
    }
  }

  Future<void> setDataSaver(bool enabled) {
    final previous = _writes;
    final release = Completer<void>();
    _writes = release.future;
    return _save(enabled, previous).whenComplete(() {
      release.complete();
      if (identical(_writes, release.future)) _writes = null;
    });
  }

  Future<void> _save(bool enabled, Future<void>? previous) async {
    if (previous != null) await previous;
    try {
      await load();
      final prefs = await preferenceStorage(SharedPreferences.getInstance);
      if (!await preferenceStorage(() => prefs.setBool(preferenceKey, enabled))) {
        throw PreferenceStorageException(StateError('Could not save media preferences.'));
      }
      _dataSaver = enabled;
      storageError = null;
    } on PreferenceStorageException catch (error) {
      storageError = error.toString();
      rethrow;
    } finally {
      notifyListeners();
    }
  }
}
