import 'package:bb_mobile/core/exchange/data/datasources/bullbitcoin_api_key_datasource.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/data/fiat_settlement_default_wallet_xprv_adapter.dart';
import 'package:bb_mobile/features/fiat_settlement/data/scoped_settlement_key_adapter.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/entities/fiat_settlement.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_configuration_events.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/scoped_settlement_key_port.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/disable_fiat_settlement_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/get_fiat_settlement_configuration_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/get_fiat_settlement_connection_status_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/is_fiat_settlement_available_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/set_fiat_settlement_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/presentation/fiat_settlement_entry_cubit.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart'
    show FiatSettlementFacade;
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:get_it/get_it.dart';

class FiatSettlementLocator {
  static void setup(GetIt locator) {
    locator.registerFactory<FiatSettlementDefaultWalletXprvPort>(
      () => FiatSettlementDefaultWalletXprvAdapter(
        getSettings: locator<GetSettingsUsecase>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );
    locator.registerFactory<ScopedSettlementKeyPort>(
      () => ScopedSettlementKeyAdapter(
        datasource: locator<BullbitcoinApiKeyDatasource>(),
        getSettings: locator<GetSettingsUsecase>(),
      ),
    );
    locator.registerFactory<GetFiatSettlementConfigurationUsecase>(
      () => GetFiatSettlementConfigurationUsecase(
        bullnym: locator<BullnymFacade>(),
        xprvPort: locator<FiatSettlementDefaultWalletXprvPort>(),
        nostrIdentity: locator<NostrIdentityFacade>(),
      ),
    );
    locator.registerFactory<GetFiatSettlementConnectionStatusUsecase>(
      () => GetFiatSettlementConnectionStatusUsecase(
        scopedKey: locator<ScopedSettlementKeyPort>(),
      ),
    );
    locator.registerFactory<SetFiatSettlementUsecase>(
      () => SetFiatSettlementUsecase(
        bullnym: locator<BullnymFacade>(),
        xprvPort: locator<FiatSettlementDefaultWalletXprvPort>(),
        nostrIdentity: locator<NostrIdentityFacade>(),
        scopedKey: locator<ScopedSettlementKeyPort>(),
      ),
    );
    locator.registerFactory<DisableFiatSettlementUsecase>(
      () => DisableFiatSettlementUsecase(
        bullnym: locator<BullnymFacade>(),
        xprvPort: locator<FiatSettlementDefaultWalletXprvPort>(),
        nostrIdentity: locator<NostrIdentityFacade>(),
      ),
    );
    locator.registerFactory<IsFiatSettlementAvailableUsecase>(
      () => IsFiatSettlementAvailableUsecase(locator<GetSettingsUsecase>()),
    );
    // Singleton: every writer must publish to the SAME event stream, or
    // the editor's save and a summary tile's listener would see different ones.
    locator.registerLazySingleton<FiatSettlementConfigurationEvents>(
      FiatSettlementConfigurationEvents.new,
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
    locator.registerFactory<FiatSettlementFacade>(
      () => FiatSettlementFacade(
        getConfiguration: locator<GetFiatSettlementConfigurationUsecase>(),
        getConnectionStatus:
            locator<GetFiatSettlementConnectionStatusUsecase>(),
        set: locator<SetFiatSettlementUsecase>(),
        disable: locator<DisableFiatSettlementUsecase>(),
        events: locator<FiatSettlementConfigurationEvents>(),
      ),
    );
  }
}
