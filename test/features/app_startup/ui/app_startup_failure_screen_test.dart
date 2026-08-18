import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/wallet/domain/inconsistent_wallet_state_exception.dart';
import 'package:bb_mobile/features/app_startup/ui/app_startup_widget.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, {Object? error}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppStartupFailureScreen(e: error, hasBackup: true),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('points wallet records without a seed at wallet recovery', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      error: InconsistentWalletStateException(fingerprint: 'f00dbabe'),
    );

    expect(find.text('Wallet data incomplete'), findsOneWidget);
    expect(
      find.textContaining('Restore your wallet from your backup'),
      findsOneWidget,
    );
    expect(find.text('Startup Error'), findsNothing);
  });

  testWidgets('keeps the generic restart advice for any other failure', (
    tester,
  ) async {
    await pumpScreen(tester, error: Exception('some storage detail'));

    expect(find.text('Startup Error'), findsOneWidget);
    expect(find.text('Wallet data incomplete'), findsNothing);
  });
}
