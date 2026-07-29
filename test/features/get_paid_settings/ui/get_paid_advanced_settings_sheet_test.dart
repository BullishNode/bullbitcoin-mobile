import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/get_paid_settings/ui/get_paid_advanced_settings_sheet.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GetPaidWalletBehavior _behavior({
  bool hideOnHome = false,
  bool autoSweep = false,
}) => GetPaidWalletBehavior(
  product: GetPaidWalletProduct.pos,
  walletId: 'w-103',
  hideOnHome: hideOnHome,
  autoSweepEnabled: autoSweep,
);

Future<void> _pump(
  WidgetTester tester, {
  required GetPaidWalletBehavior? behavior,
  bool online = true,
  bool onlineSaving = false,
  bool behaviorSaving = false,
  void Function(bool)? onOnline,
  void Function(bool)? onAutoSweep,
  void Function(bool)? onHideOnHome,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: GetPaidAdvancedSettingsSheet(
          onlineTitle: 'POS is live',
          onlineSubtitle: 'Customers can pay',
          online: online,
          onlineSaving: onlineSaving,
          onlineSavingLabel: 'Saving…',
          onOnlineChanged: onOnline ?? (_) {},
          walletBehavior: behavior,
          walletBehaviorSaving: behaviorSaving,
          onAutoSweepChanged: onAutoSweep ?? (_) {},
          onHideOnHomeChanged: onHideOnHome ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows all three controls when a wallet behavior is present', (
    tester,
  ) async {
    await _pump(tester, behavior: _behavior());

    expect(find.text('Advanced settings'), findsOneWidget);
    expect(find.text('POS is live'), findsOneWidget); // turn on/off
    expect(find.text('Auto-sweep'), findsOneWidget);
    expect(find.text('Hide on home'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(3));
  });

  testWidgets('hides the wallet-behavior controls when the wallet is missing', (
    tester,
  ) async {
    await _pump(tester, behavior: null);

    expect(find.text('POS is live'), findsOneWidget); // only turn on/off
    expect(find.text('Auto-sweep'), findsNothing);
    expect(find.text('Hide on home'), findsNothing);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets('each toggle invokes its own callback', (tester) async {
    bool? online;
    bool? autoSweep;
    bool? hide;
    await _pump(
      tester,
      // Auto-sweep on, so hide-on-home is offered at all (it is gated on it).
      behavior: _behavior(autoSweep: true),
      online: false,
      onOnline: (v) => online = v,
      onAutoSweep: (v) => autoSweep = v,
      onHideOnHome: (v) => hide = v,
    );

    await tester.tap(find.text('POS is live'));
    await tester.tap(find.text('Auto-sweep'));
    await tester.tap(find.text('Hide on home'));
    await tester.pump();

    expect(online, isTrue);
    expect(autoSweep, isFalse); // it was on
    expect(hide, isTrue);
  });

  testWidgets('a saving wallet behavior disables the behavior toggles', (
    tester,
  ) async {
    var autoSweepCalled = false;
    await _pump(
      tester,
      behavior: _behavior(),
      behaviorSaving: true,
      onAutoSweep: (_) => autoSweepCalled = true,
    );

    await tester.tap(find.text('Auto-sweep'));
    await tester.pump();

    expect(autoSweepCalled, isFalse);
  });
}
