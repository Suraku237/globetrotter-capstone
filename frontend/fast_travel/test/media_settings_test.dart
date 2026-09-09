import 'package:fast_travel/Services/media_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Data Saver defaults to enabled before and after loading', () async {
    final settings = MediaSettings();
    expect(settings.dataSaver, isTrue);
    await settings.load();
    expect(settings.dataSaver, isTrue);
    settings.dispose();
  });

  test('preference survives a new settings instance', () async {
    final settings = MediaSettings();
    await settings.setDataSaver(false);
    final restored = MediaSettings();
    await restored.load();
    expect(restored.dataSaver, isFalse);
    await restored.setDataSaver(true);
    final nextLaunch = MediaSettings();
    await nextLaunch.load();
    expect(nextLaunch.dataSaver, isTrue);
    settings.dispose();
    restored.dispose();
    nextLaunch.dispose();
  });

  test('rapid preference writes preserve the most recent choice', () async {
    final settings = MediaSettings();
    await Future.wait([
      settings.setDataSaver(false),
      settings.setDataSaver(true),
      settings.setDataSaver(false),
    ]);
    expect(settings.dataSaver, isFalse);
    final restored = MediaSettings();
    await restored.load();
    expect(restored.dataSaver, isFalse);
    settings.dispose();
    restored.dispose();
  });
}
