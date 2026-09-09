/// Normalizes native PlatformException and browser quota/security failures
/// at the preferences plugin boundary, without suppressing the original error.
class PreferenceStorageException implements Exception {
  PreferenceStorageException(this.cause);
  final Object cause;
  @override
  String toString() => 'Device storage is unavailable (${cause.runtimeType}).';
}

Future<T> preferenceStorage<T>(Future<T> Function() operation) =>
    Future<T>.sync(operation).onError((Object error, StackTrace stack) {
      Error.throwWithStackTrace(PreferenceStorageException(error), stack);
    });
