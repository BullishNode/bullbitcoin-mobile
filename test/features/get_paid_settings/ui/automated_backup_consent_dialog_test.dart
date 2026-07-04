import 'package:bb_mobile/features/get_paid_settings/ui/widgets/automated_backup_consent_dialog.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The two LOCKED strings, encoded as literals (NOT a reference to the same arb
// key) so the assertion catches any reword of the shipped copy.
const _lockedBody =
    'An encrypted backup of your wallet metadata will be created and '
    'published anonymously on NOSTR so that when you recover your wallet, the '
    'BULL app will automatically recover your Get Paid wallet. Your private '
    'keys never leave the device. This is highly recommended and does not '
    'compromise your privacy or security.';
const _lockedOffWarning =
    'You will need to manually re-enable the Get Paid feature you are '
    'activating now to recover funds you received with this feature.';

Widget _host(void Function(BuildContext context) onOpen) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => onOpen(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('body copy equals the locked string verbatim', (tester) async {
    await tester.pumpWidget(_host((context) => AutomatedBackupConsentDialog.show(context)));
    await _openDialog(tester);

    expect(find.text(_lockedBody), findsOneWidget);
  });

  testWidgets('the toggle defaults to on', (tester) async {
    await tester.pumpWidget(_host((context) => AutomatedBackupConsentDialog.show(context)));
    await _openDialog(tester);

    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isTrue);
  });

  testWidgets('turning the toggle off shows the locked warning verbatim, on '
      'removes it', (tester) async {
    await tester.pumpWidget(_host((context) => AutomatedBackupConsentDialog.show(context)));
    await _openDialog(tester);

    expect(find.text(_lockedOffWarning), findsNothing);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text(_lockedOffWarning), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text(_lockedOffWarning), findsNothing);
  });

  testWidgets('a barrier tap does not dismiss the dialog', (tester) async {
    await tester.pumpWidget(_host((context) => AutomatedBackupConsentDialog.show(context)));
    await _openDialog(tester);

    // Tap the top-left corner (the barrier area, away from the centered dialog).
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text(_lockedBody), findsOneWidget);
  });

  testWidgets('Continue returns accepted with the chosen toggle value',
      (tester) async {
    AutomatedBackupConsentResult? result;
    await tester.pumpWidget(
      _host((context) async => result = await AutomatedBackupConsentDialog.show(context)),
    );
    await _openDialog(tester);

    // Turn the toggle off, then Continue.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.accepted, isTrue);
    expect(result!.automatedBackupEnabled, isFalse);
  });

  testWidgets('a system back pop returns not accepted', (tester) async {
    AutomatedBackupConsentResult? result;
    await tester.pumpWidget(
      _host((context) async => result = await AutomatedBackupConsentDialog.show(context)),
    );
    await _openDialog(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.accepted, isFalse);
  });
}
