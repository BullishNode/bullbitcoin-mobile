import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/lightning_address_settings_datasource.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym.dart';
import 'package:bb_mobile/features/lightning_address/interface_adapters/relay_nostr_publish_adapter.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/pay_service_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/clear_lightning_address_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_status_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/publish_lightning_address_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/recover_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:get_it/get_it.dart';

class LightningAddressLocator {
  static void setup(GetIt locator) {
    if (!locator.isRegistered<BullnymClient>()) {
      locator.registerLazySingleton<BullnymClient>(() => BullnymClient());
    }
    locator.registerLazySingleton<PayServiceDatasource>(
      () => PayServiceDatasource(bullnymClient: locator<BullnymClient>()),
    );
    locator.registerLazySingleton<LightningAddressSettingsDatasource>(
      () => LightningAddressSettingsDatasource(),
    );

    locator.registerLazySingleton<PayServicePort>(
      () => locator<PayServiceDatasource>(),
    );

    locator.registerLazySingleton<NostrPublishPort>(
      () => RelayNostrPublishAdapter(relayClient: locator<NostrRelayClient>()),
    );

    locator.registerFactory<RegisterLightningAddressUsecase>(
      () => RegisterLightningAddressUsecase(
        externalReceiveWallets: locator<ExternalReceiveWalletsFacade>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        payService: locator<PayServicePort>(),
      ),
    );

    locator.registerFactory<DeleteLightningAddressUsecase>(
      () => DeleteLightningAddressUsecase(
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        payService: locator<PayServicePort>(),
      ),
    );

    locator.registerFactory<PublishLightningAddressNostrProfileUsecase>(
      () => PublishLightningAddressNostrProfileUsecase(
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        nostrPublish: locator<NostrPublishPort>(),
      ),
    );

    locator.registerFactory<ClearLightningAddressNostrProfileUsecase>(
      () => ClearLightningAddressNostrProfileUsecase(
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        nostrPublish: locator<NostrPublishPort>(),
      ),
    );

    locator.registerFactory<LookupLightningAddressStatusUsecase>(
      () => LookupLightningAddressStatusUsecase(
        payService: locator<PayServicePort>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );

    locator.registerFactory<RecoverLightningAddressUsecase>(
      () => RecoverLightningAddressUsecase(
        externalReceiveWallets: locator<ExternalReceiveWalletsFacade>(),
        payService: locator<PayServicePort>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );

    locator.registerFactory<LightningAddressCubit>(
      () => LightningAddressCubit(
        externalReceiveWallets: locator<ExternalReceiveWalletsFacade>(),
        register: locator<RegisterLightningAddressUsecase>(),
        delete: locator<DeleteLightningAddressUsecase>(),
        lookupStatus: locator<LookupLightningAddressStatusUsecase>(),
        publishProfile: locator<PublishLightningAddressNostrProfileUsecase>(),
        clearProfile: locator<ClearLightningAddressNostrProfileUsecase>(),
        payService: locator<PayServicePort>(),
        settings: locator<LightningAddressSettingsDatasource>(),
      ),
    );

    locator.registerFactory<LightningAddressFacade>(
      () => LightningAddressFacade(
        recover: locator<RecoverLightningAddressUsecase>(),
        payService: locator<PayServicePort>(),
      ),
    );
  }
}
