import 'package:fast_travel/l10n/generated/app_localizations.dart';
import 'package:fast_travel/widgets/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [400.0, 1000.0]) {
    testWidgets('community chat is reachable on a $width px screen',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdaptiveShell(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          title: 'Discover',
          onOpenFriends: () {},
          onOpenCommunity: () => opened++,
          child: const SizedBox.expand(),
        ),
      ));
      await tester.tap(find.byTooltip('Community chat'));
      expect(opened, 1);
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community chat'));
      await tester.pumpAndSettle();
      expect(opened, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
