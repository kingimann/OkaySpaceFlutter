import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/src/ui/common.dart';

void main() {
  // Regression: the offers badge keys off the 'market' nav id, not
  // 'marketplace'. With the wrong id the badge silently never rendered.
  testWidgets('marketplace (market) tab renders the offers badge', (tester) async {
    navController.value = const ['feed', 'market', 'profile'];
    marketplaceOffersBadge.value = 3;
    addTearDown(() => marketplaceOffersBadge.value = 0);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(bottomNavigationBar: OkayBottomNav(currentId: 'feed')),
    ));

    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('no badge when there are zero unread offers', (tester) async {
    navController.value = const ['feed', 'market', 'profile'];
    marketplaceOffersBadge.value = 0;

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(bottomNavigationBar: OkayBottomNav(currentId: 'feed')),
    ));

    expect(find.byType(Badge), findsNothing);
  });
}
