// Sanity tests that don't touch Firebase or the network — GlobeTrotterApp
// itself calls Firebase.initializeApp() on build (unavailable in a plain
// widget-test environment), and AppTheme.light() resolves Google Fonts
// over the network at construction, so both are avoided here in favor of
// exercising a self-contained widget under the default Material theme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fast_travel/widgets/empty_state.dart';

void main() {
  testWidgets('EmptyState renders its title, message, and retry action',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'No connection',
          message: 'Check your network and try again.',
          onRetry: () => retried = true,
        ),
      ),
    ));

    expect(find.text('No connection'), findsOneWidget);
    expect(find.text('Check your network and try again.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });
}
