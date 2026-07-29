import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/get_paid_settings/ui/get_paid_wallet_behavior_card.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _hideSwitch = Key('get_paid_hide_on_home_switch');
const _sweepSwitch = Key('get_paid_auto_sweep_switch');

GetPaidWalletBehavior _behavior({
  required bool hideOnHome,
  required bool autoSweepEnabled,
}) => GetPaidWalletBehavior(
  product: GetPaidWalletProduct.lightningAddress,
  walletId: 'w-101',
  hideOnHome: hideOnHome,
  autoSweepEnabled: autoSweepEnabled,
);

Future<List<bool>> _pump(
  WidgetTester tester,
  GetPaidWalletBehavior behavior,
) async {
  final hideWrites = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: GetPaidWalletBehaviorCard(
          behavior: behavior,
          saving: false,
          onAutoSweepChanged: (_) {},
          onHideOnHomeChanged: hideWrites.add,
        ),
      ),
    ),
  );
  await tester.pump();
  return hideWrites;
}

bool _isEnabled(WidgetTester tester, Key key) =>
    tester.widget<SwitchListTile>(find.byKey(key)).onChanged != null;

void main() {
  testWidgets('with auto-sweep off, hiding is not offered and says why', (
    tester,
  ) async {
    await _pump(tester, _behavior(hideOnHome: false, autoSweepEnabled: false));

    expect(_isEnabled(tester, _hideSwitch), isFalse);
    expect(_isEnabled(tester, _sweepSwitch), isTrue);
    expect(
      find.text(
        'Available only while auto-sweep is on: a wallet keeping its funds '
        'stays on your home list.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('with auto-sweep on, hiding is offered with its own copy', (
    tester,
  ) async {
    await _pump(tester, _behavior(hideOnHome: false, autoSweepEnabled: true));

    expect(_isEnabled(tester, _hideSwitch), isTrue);
    expect(
      find.text('Keeps this wallet off your home screen wallet list.'),
      findsOneWidget,
    );
  });

  testWidgets('a wallet already hidden can always be unhidden', (tester) async {
    // Only reachable from data written before the rule existed, but the way out
    // must never be blocked.
    final hideWrites = await _pump(
      tester,
      _behavior(hideOnHome: true, autoSweepEnabled: false),
    );

    expect(_isEnabled(tester, _hideSwitch), isTrue);
    await tester.tap(find.byKey(_hideSwitch));
    await tester.pump();
    expect(hideWrites, [false]);
  });
}
