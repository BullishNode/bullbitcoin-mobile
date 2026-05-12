import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/get_paid/shared/get_paid_nostr_identity.dart';

class GetPaidIdentityDerivation {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  const GetPaidIdentityDerivation({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  }) : _walletRepository = walletRepository,
       _seedRepository = seedRepository;

  /// Derives the single Get Paid/Bullnym Nostr signing identity.
  ///
  /// This class intentionally exposes only this operation. If another identity
  /// operation is needed, revisit whether a real Get Paid identity facade is
  /// warranted instead of growing this helper by stealth.
  Future<NostrKeychainHandle?> getSigningHandle() async {
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    final defaultWallet = wallets.firstOrNull;
    if (defaultWallet == null) return null;

    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    final xprv = Bip32Derivation.getXprvFromSeed(
      seed.bytes,
      defaultWallet.network,
    );
    return NostrKeychainHandle.deriveFromBip85(
      xprvBase58: xprv,
      identity: getPaidNostrIdentity,
      account: getPaidNostrAccount,
    );
  }
}
