import 'dart:async';

import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/disable_fiat_settlement_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/get_fiat_settlement_configuration_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/get_fiat_settlement_connection_status_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/set_fiat_settlement_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_configuration_events.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/ui/screens/fiat_settlement_editor_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/core/widgets/loading/loading_box_content.dart';
import 'package:bull_ui/bull_ui.dart' show BullButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is BullButton && w.label == label);

class _MockFacade extends Mock implements FiatSettlementFacade {}

class _MockGetConfiguration extends Mock
    implements GetFiatSettlementConfigurationUsecase {}

class _MockGetConnectionStatus extends Mock
    implements GetFiatSettlementConnectionStatusUsecase {}

class _MockSet extends Mock implements SetFiatSettlementUsecase {}

class _MockDisable extends Mock implements DisableFiatSettlementUsecase {}

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
  late _MockGetConfiguration getConfiguration;
  late _MockGetConnectionStatus getConnectionStatus;
  late _MockSet setSettlement;
  late _MockDisable disableSettlement;
  const product = FiatSettlementProduct.paymentPage;

  setUpAll(() {
    registerFallbackValue(FiatSettlementProduct.invoice);
    registerFallbackValue(FiatCurrency.cad);
  });

  setUp(() async {
    await locator.reset();
    facade = _MockFacade();
    getConfiguration = _MockGetConfiguration();
    getConnectionStatus = _MockGetConnectionStatus();
    setSettlement = _MockSet();
    disableSettlement = _MockDisable();
    when(
      () => getConfiguration.execute(),
    ).thenAnswer((_) => facade.configuration());
    when(
      () => getConnectionStatus.execute(),
    ).thenAnswer((_) async => FiatSettlementConnectionStatus.connected);
    when(
      () => setSettlement.execute(
        product: any(named: 'product'),
        fiatPercentage: any(named: 'fiatPercentage'),
        currency: any(named: 'currency'),
      ),
    ).thenAnswer(
      (invocation) => facade.set(
        product: invocation.namedArguments[#product]! as FiatSettlementProduct,
        fiatPercentage: invocation.namedArguments[#fiatPercentage]! as int,
        currency: invocation.namedArguments[#currency]! as FiatCurrency,
      ),
    );
    when(
      () => disableSettlement.execute(product: any(named: 'product')),
    ).thenAnswer(
      (invocation) => facade.disable(
        product: invocation.namedArguments[#product]! as FiatSettlementProduct,
      ),
    );
    locator.registerSingleton<GetFiatSettlementConfigurationUsecase>(
      getConfiguration,
    );
    locator.registerSingleton<GetFiatSettlementConnectionStatusUsecase>(
      getConnectionStatus,
    );
    locator.registerSingleton<SetFiatSettlementUsecase>(setSettlement);
    locator.registerSingleton<DisableFiatSettlementUsecase>(disableSettlement);
    locator.registerSingleton<FiatSettlementConfigurationEvents>(
      FiatSettlementConfigurationEvents(),
    );
  });

  tearDown(() => locator.reset());

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
    expect(_button('Connect Bull Bitcoin'), findsNothing);
    expect(_button('Log in to Bull Bitcoin'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server credential-required outcome surfaces the Connect '
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

    // Connect appears ONLY now, as the outcome of the server's answer, and it
    // is stated as a first connection rather than a repair.
    expect(_button('Connect Bull Bitcoin'), findsOneWidget);
    expect(find.text('Connect your Bull Bitcoin account'), findsOneWidget);
    expect(find.textContaining('Reconnect'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wait for the server config is named, in the app\'s own '
      'loading treatment', (tester) async {
    final answer =
        Completer<
          Result<FiatSettlementConfigurationView, FiatSettlementFailure>
        >();
    when(() => facade.configuration()).thenAnswer((_) => answer.future);

    await tester.binding.setSurfaceSize(const Size(1080, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const FiatSettlementEditorScreen(
          product: product,
          activated: true,
        ),
      ),
    );
    await tester.pump();

    // Post-activation, this read is the whole wait before the chooser appears.
    expect(
      find.text('Checking your current payout settings with Bull Bitcoin...'),
      findsOneWidget,
    );
    expect(find.byType(LoadingBoxContent), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    answer.complete(Ok(_view(product, 0)));
    await tester.pumpAndSettle();
  });
}
