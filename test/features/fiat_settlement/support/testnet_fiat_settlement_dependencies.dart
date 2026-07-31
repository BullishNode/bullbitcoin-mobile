import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/entities/fiat_settlement.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_configuration_events.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_failure.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/get_fiat_settlement_configuration_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/is_fiat_settlement_available_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/presentation/fiat_settlement_entry_cubit.dart';
import 'package:bb_mobile/locator.dart';

/// Registers the real entry-point dependency while keeping unrelated widget
/// tests on the network where fiat settlement is intentionally unavailable.
void registerTestnetFiatSettlementDependencies() {
  locator.registerSingleton<GetSettingsUsecase>(
    const _TestnetGetSettingsUsecase(),
  );
  locator.registerFactory<IsFiatSettlementAvailableUsecase>(
    () => IsFiatSettlementAvailableUsecase(locator<GetSettingsUsecase>()),
  );
  locator.registerSingleton<GetFiatSettlementConfigurationUsecase>(
    const _UnusedGetConfigurationUsecase(),
  );
  locator.registerSingleton<FiatSettlementConfigurationEvents>(
    FiatSettlementConfigurationEvents(),
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
}

final class _UnusedGetConfigurationUsecase
    implements GetFiatSettlementConfigurationUsecase {
  const _UnusedGetConfigurationUsecase();

  @override
  Future<Result<FiatSettlementConfigurationView, FiatSettlementFailure>>
  execute() {
    throw StateError('testnet availability must short-circuit configuration');
  }
}

final class _TestnetGetSettingsUsecase implements GetSettingsUsecase {
  const _TestnetGetSettingsUsecase();

  @override
  Future<SettingsEntity> execute() async => const SettingsEntity(
    environment: Environment.testnet,
    bitcoinUnit: BitcoinUnit.sats,
    currencyCode: 'CAD',
  );
}
