import 'package:bb_mobile/core/bip85/domain/derive_bip85_mnemonic_at_index_from_default_wallet_usecase.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/deterministic_wallets/application/prepare_deterministic_wallets_usecase.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';
import 'package:get_it/get_it.dart';

class DeterministicWalletsLocator {
  static void setup(GetIt locator) {
    locator.registerFactory<PrepareDeterministicWalletsUsecase>(
      () => PrepareDeterministicWalletsUsecase(
        deriveBip85:
            locator<DeriveBip85MnemonicAtIndexFromDefaultWalletUsecase>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );
    locator.registerFactory<DeterministicWalletsFacade>(
      () => DeterministicWalletsFacade(
        prepareWallets: locator<PrepareDeterministicWalletsUsecase>(),
      ),
    );
  }
}
