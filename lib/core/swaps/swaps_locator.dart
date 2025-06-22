import 'package:bb_mobile/core/blockchain/domain/repositories/liquid_blockchain_repository.dart';
import 'package:bb_mobile/core/fees/data/fees_repository.dart';
import 'package:bb_mobile/core/seed/domain/repositories/seed_repository.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/swaps/data/datasources/boltz_datasource.dart';
import 'package:bb_mobile/core/swaps/data/datasources/boltz_storage_datasource.dart';
import 'package:bb_mobile/core/swaps/data/repository/boltz_swap_repository_impl.dart';
import 'package:bb_mobile/core/swaps/data/services/auto_swap_timer_service.dart';
import 'package:bb_mobile/core/swaps/data/services/swap_watcher_impl.dart';
import 'package:bb_mobile/core/swaps/domain/repositories/swap_repository.dart';
import 'package:bb_mobile/core/swaps/domain/services/swap_watcher_service.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/create_chain_swap_to_external_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/create_chain_swap_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/decode_invoice_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_auto_swap_settings_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_swap_limits_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_swap_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_swaps_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/process_swap_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/restart_swap_watcher_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/save_auto_swap_settings_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/update_paid_chain_swap_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/watch_swap_usecase.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_repository.dart';
import 'package:bb_mobile/locator.dart';

class SwapsLocator {
  static Future<void> registerDatasources() async {
    locator.registerLazySingleton<BoltzStorageDatasource>(
      () => BoltzStorageDatasource(
        secureSwapStorage: locator<KeyValueStorageDatasource<String>>(
          instanceName: LocatorInstanceNameConstants.secureStorageDatasource,
        ),
        localSwapStorage: locator<SqliteDatabase>(),
      ),
    );
  }

  static void registerRepositories() {
    locator.registerLazySingleton<SwapRepository>(
      () => BoltzSwapRepositoryImpl(
        boltz: BoltzDatasource(
          url: ApiServiceConstants.boltzTestnetUrlPath,
          boltzStore: locator<BoltzStorageDatasource>(),
        ),
      ),
      instanceName:
          LocatorInstanceNameConstants.boltzTestnetSwapRepositoryInstanceName,
    );

    locator.registerLazySingleton<SwapRepository>(
      () => BoltzSwapRepositoryImpl(
        boltz: BoltzDatasource(boltzStore: locator<BoltzStorageDatasource>()),
      ),
      instanceName:
          LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
    );
  }

  static void registerServices() {
    // add swap watcher service
    locator.registerLazySingleton<SwapWatcherService>(
      () => SwapWatcherServiceImpl(
        boltzRepo:
            locator<SwapRepository>(
                  instanceName:
                      LocatorInstanceNameConstants
                          .boltzSwapRepositoryInstanceName,
                )
                as BoltzSwapRepositoryImpl,
        walletAddressRepository: locator<WalletAddressRepository>(),
        settingsRepository: locator<SettingsRepository>(),
        feesRepository: locator<FeesRepository>(),
      ),
      instanceName: LocatorInstanceNameConstants.boltzSwapWatcherInstanceName,
    );

    // add swap watcher service
    locator.registerLazySingleton<SwapWatcherService>(
      () => SwapWatcherServiceImpl(
        boltzRepo:
            locator<SwapRepository>(
                  instanceName:
                      LocatorInstanceNameConstants
                          .boltzTestnetSwapRepositoryInstanceName,
                )
                as BoltzSwapRepositoryImpl,
        walletAddressRepository: locator<WalletAddressRepository>(),
        settingsRepository: locator<SettingsRepository>(),
        feesRepository: locator<FeesRepository>(),
      ),
      instanceName:
          LocatorInstanceNameConstants.boltzTestnetSwapWatcherInstanceName,
    );

    // add auto swap timer service for mainnet
    final mainnetAutoSwapTimer = AutoSwapTimerService(
      swapRepository: locator<SwapRepository>(
        instanceName:
            LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
      ),
      walletRepository: locator<WalletRepository>(),
      liquidWalletRepository: locator<LiquidWalletRepository>(),
      liquidBlockchainRepository: locator<LiquidBlockchainRepository>(),
      seedRepository: locator<SeedRepository>(),
    );
    mainnetAutoSwapTimer.startTimer();
    locator.registerLazySingleton<AutoSwapTimerService>(
      () => mainnetAutoSwapTimer,
      instanceName: LocatorInstanceNameConstants.boltzAutoSwapTimerInstanceName,
    );

    // add auto swap timer service for testnet
    final testnetAutoSwapTimer = AutoSwapTimerService(
      swapRepository: locator<SwapRepository>(
        instanceName:
            LocatorInstanceNameConstants.boltzTestnetSwapRepositoryInstanceName,
      ),
      walletRepository: locator<WalletRepository>(),
      liquidWalletRepository: locator<LiquidWalletRepository>(),
      liquidBlockchainRepository: locator<LiquidBlockchainRepository>(),
      seedRepository: locator<SeedRepository>(),
    );
    testnetAutoSwapTimer.startTimer();
    locator.registerLazySingleton<AutoSwapTimerService>(
      () => testnetAutoSwapTimer,
      instanceName:
          LocatorInstanceNameConstants.boltzTestnetAutoSwapTimerInstanceName,
    );
  }

  static void registerUsecases() {
    locator.registerFactory<DecodeInvoiceUsecase>(
      () => DecodeInvoiceUsecase(
        mainnetSwapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
        ),
        testnetSwapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants
                  .boltzTestnetSwapRepositoryInstanceName,
        ),
      ),
    );

    locator.registerFactory<GetSwapLimitsUsecase>(
      () => GetSwapLimitsUsecase(
        mainnetSwapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
        ),
        testnetSwapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants
                  .boltzTestnetSwapRepositoryInstanceName,
        ),
      ),
    );

    locator.registerFactory<RestartSwapWatcherUsecase>(
      () => RestartSwapWatcherUsecase(
        swapWatcherService: locator<SwapWatcherService>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapWatcherInstanceName,
        ),
      ),
    );

    locator.registerFactory<GetSwapUsecase>(
      () => GetSwapUsecase(
        mainnetSwapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
        ),
        testnetSwapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants
                  .boltzTestnetSwapRepositoryInstanceName,
        ),
      ),
    );

    locator.registerFactory<GetSwapsUsecase>(
      () => GetSwapsUsecase(
        mainnetSwapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
        ),
        testnetSwapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants
                  .boltzTestnetSwapRepositoryInstanceName,
        ),
        settingsRepository: locator<SettingsRepository>(),
      ),
    );

    locator.registerFactory<WatchSwapUsecase>(
      () => WatchSwapUsecase(
        watcherService: locator<SwapWatcherService>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapWatcherInstanceName,
        ),
      ),
    );
    locator.registerFactory<UpdatePaidChainSwapUsecase>(
      () => UpdatePaidChainSwapUsecase(
        swapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
        ),
        swapRepositoryTestnet: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants
                  .boltzTestnetSwapRepositoryInstanceName,
        ),
      ),
    );
    locator.registerFactory<GetAutoSwapSettingsUsecase>(
      () => GetAutoSwapSettingsUsecase(
        mainnetRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
        ),
        testnetRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants
                  .boltzTestnetSwapRepositoryInstanceName,
        ),
      ),
    );
    locator.registerFactory<SaveAutoSwapSettingsUsecase>(
      () => SaveAutoSwapSettingsUsecase(
        mainnetRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
        ),
        testnetRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants
                  .boltzTestnetSwapRepositoryInstanceName,
        ),
      ),
    );
    locator.registerFactory<CreateChainSwapUsecase>(
      () => CreateChainSwapUsecase(
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        swapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
        ),
        swapRepositoryTestnet: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants
                  .boltzTestnetSwapRepositoryInstanceName,
        ),
      ),
    );
    locator.registerFactory<CreateChainSwapToExternalUsecase>(
      () => CreateChainSwapToExternalUsecase(
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        swapRepository: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapRepositoryInstanceName,
        ),
        swapRepositoryTestnet: locator<SwapRepository>(
          instanceName:
              LocatorInstanceNameConstants
                  .boltzTestnetSwapRepositoryInstanceName,
        ),
      ),
    );
    locator.registerFactory<ProcessSwapUsecase>(
      () => ProcessSwapUsecase(
        watcherService: locator<SwapWatcherService>(
          instanceName:
              LocatorInstanceNameConstants.boltzSwapWatcherInstanceName,
        ),
      ),
    );
  }
}
