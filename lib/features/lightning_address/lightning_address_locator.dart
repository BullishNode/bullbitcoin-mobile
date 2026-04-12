import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/pay_service_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/sweep_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:get_it/get_it.dart';

class LightningAddressLocator {
  static void setup(GetIt locator) {
    locator.registerLazySingleton<PayServiceDatasource>(
      () => PayServiceDatasource(),
    );

    locator.registerFactory<GetLightningAddressWalletUsecase>(
      () => GetLightningAddressWalletUsecase(
        walletRepository: locator<WalletRepository>(),
      ),
    );

    locator.registerFactory<CreateLightningAddressWalletUsecase>(
      () => CreateLightningAddressWalletUsecase(
        bip85Repository: locator<Bip85Repository>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        getWallet: locator<GetLightningAddressWalletUsecase>(),
      ),
    );

    locator.registerFactory<SweepLightningAddressWalletUsecase>(
      () => SweepLightningAddressWalletUsecase(
        getWallet: locator<GetLightningAddressWalletUsecase>(),
        walletRepository: locator<WalletRepository>(),
        walletAddressRepository: locator<WalletAddressRepository>(),
        liquidWalletRepository: locator<LiquidWalletRepository>(),
        broadcast: locator<BroadcastLiquidTransactionUsecase>(),
      ),
    );

    locator.registerFactory<RegisterLightningAddressUsecase>(
      () => RegisterLightningAddressUsecase(
        createWallet: locator<CreateLightningAddressWalletUsecase>(),
        getWallet: locator<GetLightningAddressWalletUsecase>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        payService: locator<PayServiceDatasource>(),
      ),
    );

    locator.registerFactory<DeleteLightningAddressUsecase>(
      () => DeleteLightningAddressUsecase(
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        payService: locator<PayServiceDatasource>(),
      ),
    );

    locator.registerFactory<LightningAddressCubit>(
      () => LightningAddressCubit(
        getWallet: locator<GetLightningAddressWalletUsecase>(),
        register: locator<RegisterLightningAddressUsecase>(),
        delete: locator<DeleteLightningAddressUsecase>(),
        payService: locator<PayServiceDatasource>(),
      ),
    );

    locator.registerFactory<LightningAddressFacade>(
      () => LightningAddressFacade(
        sweep: locator<SweepLightningAddressWalletUsecase>(),
      ),
    );
  }
}
