import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/pos/ui/widgets/pos_staff_instructions.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(
        body: SingleChildScrollView(child: PosStaffInstructions()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('instructions are collapsed until the button is tapped', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Instructions for staff'), findsOneWidget);
    // Collapsed: the verbatim heading is not shown yet.
    expect(
      find.text('Two ways for your staff to accept Bitcoin payments'),
      findsNothing,
    );
  });

  testWidgets('tapping the button expands the owner-verbatim instructions '
      'below, in order', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Instructions for staff'));
    await tester.pumpAndSettle();

    // Every owner sentence renders exactly as written.
    expect(
      find.text('Two ways for your staff to accept Bitcoin payments'),
      findsOneWidget,
    );
    expect(
      find.text(
        'If your cashiers already have a tablet, scan this QR code with the '
        'tablet. It will open up the web Point of Sale page for your business.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'You can print this QR code and your staff can scan it with their '
        'personal phones. There is no security risk.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Your staff simply need to enter the amount of the sale in the web '
        'page. It will generate a payment request with a QR code. They must '
        'show the QR code to the client that wants to pay with Bitcoin. They '
        'can enter a description for the payment if you wish.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Pro tip: Lightning and Liquid payments are instant. Bitcoin on-chain '
        'payments can take up to an hour to confirm. You should not accept '
        'Bitcoin on-chain payments in a physical store unless the client '
        'insists and is willing to wait.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'You, the business owner that set up the point of sale, will receive '
        'the funds. Your staff will never have access to the funds if you '
        'follow these instructions.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
