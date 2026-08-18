import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/get_get_paid_fiat_settlement_summary_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _FiatSettlementFacade extends Mock implements FiatSettlementFacade {}

class _GetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _Settings extends Mock implements SettingsEntity {}

void main() {
  late _FiatSettlementFacade fiat;
  late _GetSettingsUsecase getSettings;
  late _Settings settings;

  setUp(() {
    fiat = _FiatSettlementFacade();
    getSettings = _GetSettingsUsecase();
    settings = _Settings();
    when(() => getSettings.execute()).thenAnswer((_) async => settings);
  });

  test('maps only the three dashboard product configurations', () async {
    when(() => settings.environment).thenReturn(Environment.mainnet);
    when(() => fiat.configuration()).thenAnswer(
      (_) async => const Ok(
        FiatSettlementConfigurationView(
          products: [
            FiatSettlementProductConfig(
              product: FiatSettlementProduct.paymentPage,
              fiatPercentage: 50,
              currency: FiatCurrency.cad,
            ),
          ],
          credentialActive: true,
        ),
      ),
    );
    final usecase = GetGetPaidFiatSettlementSummaryUsecase(
      fiatSettlement: fiat,
      getSettings: getSettings,
    );

    final summary = await usecase.execute();

    expect(summary?.isUnavailable, isFalse);
    expect(summary?.configs.length, 3);
    final page =
        summary?.configs[GetPaidDashboardSettlementProduct.paymentPage];
    expect(page?.fiatPercentage, 50);
    expect(page?.currencyCode, 'CAD');
  });

  test('is absent off mainnet and unavailable on a rejected read', () async {
    final usecase = GetGetPaidFiatSettlementSummaryUsecase(
      fiatSettlement: fiat,
      getSettings: getSettings,
    );
    when(() => settings.environment).thenReturn(Environment.testnet);
    expect(await usecase.execute(), isNull);

    when(() => settings.environment).thenReturn(Environment.mainnet);
    when(() => fiat.configuration()).thenAnswer(
      (_) async => const Err(FiatSettlementFailure.bullnymUnreachable()),
    );
    expect((await usecase.execute())?.isUnavailable, isTrue);
  });
}
