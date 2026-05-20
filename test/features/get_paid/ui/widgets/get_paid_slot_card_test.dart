import 'dart:ui' show Tristate;

import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/get_paid/ui/widgets/get_paid_slot_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('enabled card is tappable and shows the navigation arrow', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _harness(
        GetPaidSlotCard(
          icon: Icons.receipt_long,
          title: 'Invoices',
          subtitle: 'Create and manage invoices',
          onPressed: () => tapped = true,
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    final semantics = tester.getSemantics(_cardSemantics);
    final semanticsData = semantics.getSemanticsData();
    expect(semanticsData.flagsCollection.isButton, isTrue);
    expect(semanticsData.flagsCollection.isEnabled, Tristate.isTrue);
    expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.text('Invoices'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('disabled card is not tappable and hides the navigation arrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const GetPaidSlotCard(
          icon: Icons.storefront,
          title: 'Payment Page',
          subtitle: 'Choose a Bullnym name first',
          onPressed: null,
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    final semantics = tester.getSemantics(_cardSemantics);
    final semanticsData = semantics.getSemanticsData();
    expect(semanticsData.flagsCollection.isButton, isTrue);
    expect(semanticsData.flagsCollection.isEnabled, Tristate.isFalse);
    expect(semanticsData.hasAction(SemanticsAction.tap), isFalse);

    await tester.tap(find.text('Payment Page'));
    await tester.pump();
  });
}

Widget _harness(Widget child) {
  return MaterialApp(
    theme: AppTheme.themeData(AppThemeType.light),
    home: Scaffold(body: child),
  );
}

Finder get _cardSemantics {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.button == true,
  );
}
