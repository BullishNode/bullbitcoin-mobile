import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/seed/domain/seed_failure.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';

abstract interface class DeterministicWalletRepository {
  Future<PreparedDeterministicWallet?> getMatchingWallet({
    required MnemonicSeed seedPreview,
    required DeterministicWalletSpec spec,
  });

  Future<bool> childSeedExists(String fingerprint);

  Future<MnemonicSeed> storeChildSeed(MnemonicSeed seedPreview);

  Future<PreparedDeterministicWallet> createWallet({
    required MnemonicSeed childSeed,
    required DeterministicWalletSpec spec,
  });

  Future<void> deleteWallet(String walletId);

  Future<Result<void, SeedDeleteFailure>> deleteChildSeed(String fingerprint);
}
