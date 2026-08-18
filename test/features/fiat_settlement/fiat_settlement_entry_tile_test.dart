import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/entities/fiat_settlement.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_failure.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/get_fiat_settlement_configuration_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/is_fiat_settlement_available_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/presentation/fiat_settlement_entry_cubit.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_configuration_events.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_entry_tile.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetConfiguration extends Mock
    implements GetFiatSettlementConfigurationUsecase {}

class _FakeGetSettings implements GetSettingsUsecase {
  @override
  Future<SettingsEntity> execute() async => const SettingsEntity(
    environment: Environment.mainnet,
    bitcoinUnit: BitcoinUnit.sats,
    currencyCode: 'CAD',
  );
}

Future<void> _pumpTile(WidgetTester tester) async {
  locator.registerFactory<IsFiatSettlementAvailableUsecase>(
    () => IsFiatSettlementAvailableUsecase(locator<GetSettingsUsecase>()),
  );
  locator.registerFactoryParam<
    FiatSettlementEntryCubit,
    FiatSettlementProduct,
    void
  >(
    (product, _) => FiatSettlementEntryCubit(
      product: product,
      availability: locator<IsFiatSettlementAvailableUsecase>(),
      getConfiguration: locator<GetFiatSettlementConfigurationUsecase>(),
      events: locator<FiatSettlementConfigurationEvents>(),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(
        body: FiatSettlementEntryTile(product: FiatSettlementProduct.invoice),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => locator.reset());

  testWidgets('shows an honest unavailable state on a read failure', (
    tester,
  ) async {
    final getConfiguration = _MockGetConfiguration();
    when(
      () => getConfiguration.execute(),
    ).thenAnswer((_) async => const Err(FiatSettlementFailure.unexpected()));
    locator
      ..registerSingleton<GetSettingsUsecase>(_FakeGetSettings())
      ..registerSingleton<GetFiatSettlementConfigurationUsecase>(
        getConfiguration,
      )
      ..registerSingleton<FiatSettlementConfigurationEvents>(
        FiatSettlementConfigurationEvents(),
      );

    await _pumpTile(tester);

    // The tile is visible and honest: it shows the unavailable status and NEVER
    // fabricates a Bitcoin-only summary from the failure.
    expect(find.byKey(const ValueKey('fiat-settlement-entry-tile')), findsOne);
    expect(find.text('Fiat settlement — status unavailable'), findsOneWidget);
    expect(find.text('Bitcoin only'), findsNothing);
  });

  testWidgets('shows the confirmed summary when configuration loads', (
    tester,
  ) async {
    final getConfiguration = _MockGetConfiguration();
    when(() => getConfiguration.execute()).thenAnswer(
      (_) async => const Ok(
        FiatSettlementConfigurationView(products: [], credentialActive: false),
      ),
    );
    locator
      ..registerSingleton<GetSettingsUsecase>(_FakeGetSettings())
      ..registerSingleton<GetFiatSettlementConfigurationUsecase>(
        getConfiguration,
      )
      ..registerSingleton<FiatSettlementConfigurationEvents>(
        FiatSettlementConfigurationEvents(),
      );

    await _pumpTile(tester);

    // An absent product config is Bitcoin-only — a real confirmed summary,
    // distinct from the failure state above.
    expect(find.text('Bitcoin only'), findsOneWidget);
    expect(find.text('Fiat settlement — status unavailable'), findsNothing);
  });

  testWidgets(
    're-reads when the configuration revision bumps after an outside mutation',
    (tester) async {
      // Regression: the activation-time chooser saves fiat settlement WITHOUT
      // passing through the tile's own tap round-trip. The tile used to keep
      // its mount-time snapshot ("Bitcoin only") until the screen was
      // revisited; it must re-read when the shared revision notifies.
      final getConfiguration = _MockGetConfiguration();
      final revision = FiatSettlementConfigurationEvents();
      var config = const FiatSettlementConfigurationView(
        products: [],
        credentialActive: false,
      );
      when(
        () => getConfiguration.execute(),
      ).thenAnswer((_) async => Ok(config));
      locator
        ..registerSingleton<GetSettingsUsecase>(_FakeGetSettings())
        ..registerSingleton<GetFiatSettlementConfigurationUsecase>(
          getConfiguration,
        )
        ..registerSingleton<FiatSettlementConfigurationEvents>(revision);

      await _pumpTile(tester);
      expect(find.text('Bitcoin only'), findsOneWidget);

      // The chooser saves 100% fiat EUR elsewhere; the facade bumps.
      config = const FiatSettlementConfigurationView(
        products: [
          FiatSettlementProductConfig(
            product: FiatSettlementProduct.invoice,
            fiatPercentage: 100,
            currency: FiatCurrency.eur,
          ),
        ],
        credentialActive: true,
      );
      revision.notifyChanged();
      await tester.pumpAndSettle();

      expect(find.text('Bitcoin only'), findsNothing);
      expect(find.textContaining('100%'), findsOneWidget);
    },
  );
}
