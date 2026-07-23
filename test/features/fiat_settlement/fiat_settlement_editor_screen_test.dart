import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/has_bull_bitcoin_account_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/ui/screens/fiat_settlement_editor_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bull_ui/bull_ui.dart' show BullButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is BullButton && w.label == label);

class _MockFacade extends Mock implements FiatSettlementFacade {}

class _MockHasAccount extends Mock implements HasBullBitcoinAccountUsecase {}

FiatSettlementConfigurationView _view(
  FiatSettlementProduct product,
  int pct, {
  FiatCurrency? currency,
}) {
  return FiatSettlementConfigurationView(
    products: [
      FiatSettlementProductConfig(
        product: product,
        fiatPercentage: pct,
        currency: currency,
      ),
    ],
    credentialActive: true,
  );
}

void main() {
  late _MockFacade facade;
  late _MockHasAccount hasAccount;
  const product = FiatSettlementProduct.paymentPage;

  setUp(() {
    facade = _MockFacade();
    hasAccount = _MockHasAccount();
    if (locator.isRegistered<FiatSettlementFacade>()) {
      locator.unregister<FiatSettlementFacade>();
    }
    if (locator.isRegistered<HasBullBitcoinAccountUsecase>()) {
      locator.unregister<HasBullBitcoinAccountUsecase>();
    }
    locator.registerFactory<FiatSettlementFacade>(() => facade);
    locator.registerFactory<HasBullBitcoinAccountUsecase>(() => hasAccount);
  });

  tearDown(() {
    if (locator.isRegistered<FiatSettlementFacade>()) {
      locator.unregister<FiatSettlementFacade>();
    }
    if (locator.isRegistered<HasBullBitcoinAccountUsecase>()) {
      locator.unregister<HasBullBitcoinAccountUsecase>();
    }
  });

  Future<void> pump(WidgetTester tester) async {
    // A tall surface so the whole scrolling form (incl. the bottom action
    // button) is laid out and findable without scrolling.
    await tester.binding.setSurfaceSize(const Size(1080, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const FiatSettlementEditorScreen(product: product),
      ),
    );
    // Let load() (two awaited reads) complete and the form settle.
    await tester.pumpAndSettle();
  }

  testWidgets('a saved active split renders with a secondary reconnect (never '
      'a login panel that hides it) when unauthenticated', (tester) async {
    when(() => facade.configuration()).thenAnswer(
      (_) async => Ok(_view(product, 50, currency: FiatCurrency.cad)),
    );
    when(() => hasAccount.execute()).thenAnswer((_) async => false);

    await pump(tester);

    // The saved split is displayed — the mix chooser option is present.
    expect(find.text('A mix of Bitcoin and fiat'), findsOneWidget);
    // The secondary reconnect stands in for Save; the old login panel is gone.
    expect(_button('Reconnect Bull Bitcoin'), findsOneWidget);
    expect(_button('Log in to Bull Bitcoin'), findsNothing);
    expect(_button('Save'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an authenticated editor shows Save, not reconnect', (
    tester,
  ) async {
    when(() => facade.configuration()).thenAnswer(
      (_) async => Ok(_view(product, 50, currency: FiatCurrency.cad)),
    );
    when(() => hasAccount.execute()).thenAnswer((_) async => true);

    await pump(tester);

    expect(_button('Save'), findsOneWidget);
    expect(_button('Reconnect Bull Bitcoin'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
