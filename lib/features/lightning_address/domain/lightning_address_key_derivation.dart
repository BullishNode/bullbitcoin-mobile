import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';

/// Derives the xprv from the default Bitcoin wallet.
/// Shared by all Lightning Address use cases that need BIP85 derivation.
Future<String> deriveDefaultWalletXprv({
  required WalletRepository walletRepository,
  required SeedRepository seedRepository,
}) async {
  final wallets = await walletRepository.getWallets(
    onlyDefaults: true,
    onlyBitcoin: true,
  );
  if (wallets.isEmpty) throw LightningAddressNoDefaultWalletException();
  final defaultWallet = wallets.first;

  final seed = await seedRepository.get(defaultWallet.masterFingerprint);
  return Bip32Derivation.getXprvFromSeed(seed.bytes, defaultWallet.network);
}

/// Derives the Lightning Address Nostr identity from the default Bitcoin wallet.
/// Returns null if no default wallet is available.
Future<NostrIdentity?> deriveNostrIdentityForLightningAddress({
  required WalletRepository walletRepository,
  required SeedRepository seedRepository,
}) async {
  try {
    final xprv = await deriveDefaultWalletXprv(
      walletRepository: walletRepository,
      seedRepository: seedRepository,
    );
    return NostrIdentity.derive(
      xprvBase58: xprv,
      identity: lightningAddressNostrIdentity,
      account: lightningAddressNostrAccount,
    );
  } on LightningAddressNoDefaultWalletException {
    return null;
  }
}

NostrKeychainHandle deriveNostrHandleFromXprvForLightningAddress(
  String xprvBase58,
) {
  return NostrKeychainHandle.deriveFromBip85(
    xprvBase58: xprvBase58,
    identity: lightningAddressNostrIdentity,
    account: lightningAddressNostrAccount,
  );
}
