import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/features/wallet/ui/widgets/wallet_bottom_buttons.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('send button is disabled when sendDisabled is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: WalletBottomButtons(sendDisabled: true)),
      ),
    );

    final sendButton = tester.widget<BBButton>(
      find.byWidgetPredicate(
        (widget) => widget is BBButton && widget.label == 'Send',
      ),
    );

    expect(sendButton.disabled, isTrue);
  });
}
