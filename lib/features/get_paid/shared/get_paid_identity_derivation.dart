import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity.dart';

class GetPaidIdentityDerivation {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  const GetPaidIdentityDerivation({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  }) : _walletRepository = walletRepository,
       _seedRepository = seedRepository;

  /// Derives the Bullnym server-authentication Nostr signing identity.
  ///
  /// Keep this helper narrow. If Get Paid needs more identity operations,
  /// introduce an explicit facade instead of expanding this class ad hoc.
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
    return deriveBullnymServerAuthHandleFromXprv(xprv);
  }
}
