import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
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
  const product = FiatSettlementProduct.paymentPage;

  setUpAll(() {
    registerFallbackValue(FiatSettlementProduct.invoice);
    registerFallbackValue(FiatCurrency.cad);
  });

  setUp(() {
    facade = _MockFacade();
    if (locator.isRegistered<FiatSettlementFacade>()) {
      locator.unregister<FiatSettlementFacade>();
    }
    locator.registerFactory<FiatSettlementFacade>(() => facade);
  });

  tearDown(() {
    if (locator.isRegistered<FiatSettlementFacade>()) {
      locator.unregister<FiatSettlementFacade>();
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

  testWidgets('a saved active split renders AND is savable — no local account '
      'gate, no login panel, no standalone reconnect', (tester) async {
    // There is no exchange-login concept in the editor anymore: the saved
    // split shows, and Save is offered directly (a keyless npm-signed save).
    when(() => facade.configuration()).thenAnswer(
      (_) async => Ok(_view(product, 50, currency: FiatCurrency.cad)),
    );

    await pump(tester);

    // The saved split is displayed — the mix chooser option is present.
    expect(find.text('A mix of Bitcoin and fiat'), findsOneWidget);
    // Save is offered directly; the old pre-gate reconnect/login panel is gone.
    expect(_button('Save'), findsOneWidget);
    expect(_button('Reconnect Bull Bitcoin'), findsNothing);
    expect(_button('Log in to Bull Bitcoin'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server credential-required outcome surfaces the Reconnect '
      'action (the only path that needs the exchange login)', (tester) async {
    when(() => facade.configuration()).thenAnswer(
      (_) async => Ok(_view(product, 50, currency: FiatCurrency.cad)),
    );
    // The keyless save is rejected by the server for want of a stored key.
    when(
      () => facade.set(
        product: any(named: 'product'),
        fiatPercentage: any(named: 'fiatPercentage'),
        currency: any(named: 'currency'),
      ),
    ).thenAnswer(
      (_) async => const Err(FiatSettlementFailure.credentialProblem()),
    );

    await pump(tester);
    await tester.tap(_button('Save'));
    await tester.pumpAndSettle();

    // Reconnect appears ONLY now, as the outcome of the server's answer.
    expect(_button('Reconnect Bull Bitcoin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
