import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity.dart';

/// Derives the xprv from the default Bitcoin wallet.
/// Shared by all Lightning Address use cases that need BIP85 derivation.
///
/// This duplicates the Get Paid identity policy in
/// `features/get_paid/shared/get_paid_identity_derivation.dart`. The remaining
/// `NostrIdentity` call sites should move to the shared helper in a dedicated
/// Lightning Address cleanup.
Future<String> deriveDefaultWalletXprv({
  required WalletRepository walletRepository,
  required SeedRepository seedRepository,
  Environment? environment,
}) async {
  final wallets = await walletRepository.getWallets(
    environment: environment,
    onlyDefaults: true,
    onlyBitcoin: true,
  );
  if (wallets.isEmpty) throw LightningAddressNoDefaultWalletException();
  final defaultWallet = wallets.first;

  final seed = await seedRepository.get(defaultWallet.masterFingerprint);
  return Bip32Derivation.getXprvFromSeed(seed.bytes, defaultWallet.network);
}

/// Derives the Lightning Address Bullnym auth identity from the default Bitcoin wallet.
/// Returns null if no default wallet is available.
Future<NostrIdentity?> deriveBullnymServerAuthIdentityForLightningAddress({
  required WalletRepository walletRepository,
  required SeedRepository seedRepository,
  Environment? environment,
}) async {
  try {
    final xprv = await deriveDefaultWalletXprv(
      walletRepository: walletRepository,
      seedRepository: seedRepository,
      environment: environment,
    );
    return deriveBullnymServerAuthIdentityFromXprv(xprv);
  } on LightningAddressNoDefaultWalletException {
    return null;
  }
}

NostrKeychainHandle deriveBullnymServerAuthHandleFromXprvForLightningAddress(
  String xprvBase58,
) {
  return deriveBullnymServerAuthHandleFromXprv(xprvBase58);
}

NostrKeychainHandle deriveNip05VerificationHandleFromXprvForLightningAddress(
  String xprvBase58,
) {
  return deriveNip05VerificationHandleFromXprv(xprvBase58);
}
