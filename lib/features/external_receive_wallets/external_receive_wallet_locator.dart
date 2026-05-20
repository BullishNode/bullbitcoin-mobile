import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_bitcoin_transaction_usecase.dart';
import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/get_network_fees_usecase.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_auto_swap_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/bitcoin_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:bb_mobile/features/external_receive_wallets/data/external_receive_wallet_settings_datasource.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets_facade.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/create_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/delete_created_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/restore_reserved_external_receive_wallets_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/resolve_external_receive_wallet_ids_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/sweep_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';
import 'package:get_it/get_it.dart';

class ExternalReceiveWalletLocator {
  static void setup(GetIt locator) {
    if (!locator.isRegistered<ExternalReceiveWalletSettingsDatasource>()) {
      locator.registerLazySingleton<ExternalReceiveWalletSettingsDatasource>(
        () => ExternalReceiveWalletSettingsDatasource(),
      );
    }

    if (!locator.isRegistered<WalletLabelReservationPolicy>()) {
      locator.registerLazySingleton<WalletLabelReservationPolicy>(
        () => const WalletLabelReservationPolicy(
          reservedLabels: ReservedExternalReceiveWalletLabel.userReserved,
        ),
      );
    }

    if (!locator.isRegistered<GetExternalReceiveWalletUsecase>()) {
      locator.registerFactory<GetExternalReceiveWalletUsecase>(
        () => GetExternalReceiveWalletUsecase(
          walletRepository: locator<WalletRepository>(),
          walletManifest: locator<WalletManifestFacade>(),
        ),
      );
    }

    if (!locator.isRegistered<CreateExternalReceiveWalletUsecase>()) {
      locator.registerFactory<CreateExternalReceiveWalletUsecase>(
        () => CreateExternalReceiveWalletUsecase(
          bip85Repository: locator<Bip85Repository>(),
          walletRepository: locator<WalletRepository>(),
          seedRepository: locator<SeedRepository>(),
          getWallet: locator<GetExternalReceiveWalletUsecase>(),
          walletManifest: locator<WalletManifestFacade>(),
        ),
      );
    }

    if (!locator.isRegistered<RestoreReservedExternalReceiveWalletsUsecase>()) {
      locator.registerFactory<RestoreReservedExternalReceiveWalletsUsecase>(
        () => RestoreReservedExternalReceiveWalletsUsecase(
          getWallet: locator<GetExternalReceiveWalletUsecase>(),
          createWallet: locator<CreateExternalReceiveWalletUsecase>(),
          walletManifest: locator<WalletManifestFacade>(),
        ),
      );
    }

    if (!locator.isRegistered<DeleteCreatedExternalReceiveWalletUsecase>()) {
      locator.registerFactory<DeleteCreatedExternalReceiveWalletUsecase>(
        () => DeleteCreatedExternalReceiveWalletUsecase(
          getWallet: locator<GetExternalReceiveWalletUsecase>(),
          walletRepository: locator<WalletRepository>(),
        ),
      );
    }

    if (!locator.isRegistered<SweepExternalReceiveWalletUsecase>()) {
      locator.registerFactory<SweepExternalReceiveWalletUsecase>(
        () => SweepExternalReceiveWalletUsecase(
          getWallet: locator<GetExternalReceiveWalletUsecase>(),
          walletRepository: locator<WalletRepository>(),
          walletAddressRepository: locator<WalletAddressRepository>(),
          liquidWalletRepository: locator<LiquidWalletRepository>(),
          bitcoinWalletRepository: locator<BitcoinWalletRepository>(),
          broadcastLiquid: locator<BroadcastLiquidTransactionUsecase>(),
          broadcastBitcoin: locator<BroadcastBitcoinTransactionUsecase>(),
          getNetworkFees: locator<GetNetworkFeesUsecase>(),
          getAutoSwapSettings: locator<GetAutoSwapSettingsUsecase>(),
          labelsFacade: locator<LabelsFacade>(),
        ),
      );
    }

    if (!locator.isRegistered<ResolveExternalReceiveWalletIdsUsecase>()) {
      locator.registerFactory<ResolveExternalReceiveWalletIdsUsecase>(
        () => ResolveExternalReceiveWalletIdsUsecase(
          walletManifest: locator<WalletManifestFacade>(),
          settings: locator<ExternalReceiveWalletSettingsDatasource>(),
        ),
      );
    }

    if (!locator.isRegistered<ExternalReceiveWalletsFacade>()) {
      locator.registerFactory<ExternalReceiveWalletsFacade>(
        () => ExternalReceiveWalletsFacade(
          getWallet: locator<GetExternalReceiveWalletUsecase>(),
          createWallet: locator<CreateExternalReceiveWalletUsecase>(),
          deleteCreatedWallet:
              locator<DeleteCreatedExternalReceiveWalletUsecase>(),
          restoreReservedWallets:
              locator<RestoreReservedExternalReceiveWalletsUsecase>(),
          sweepWallet: locator<SweepExternalReceiveWalletUsecase>(),
          resolveWalletIds: locator<ResolveExternalReceiveWalletIdsUsecase>(),
          settings: locator<ExternalReceiveWalletSettingsDatasource>(),
        ),
      );
    }
  }
}
