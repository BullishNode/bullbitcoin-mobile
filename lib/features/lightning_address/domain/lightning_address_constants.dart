import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';

const String lightningAddressWalletLabel = 'Lightning Address';
const String lightningAddressDomain = 'bullpay.ca';
const String payServiceBaseUrl = 'https://bullpay.ca';

/// BIP85 index for the Lightning Address receive wallet (boltz = 75).
const int lightningAddressWalletBip85Index = 75;

/// Nostr identity/account indices for pay service authentication.
const int lightningAddressNostrIdentity = 75;
const int lightningAddressNostrAccount = 0;

/// Derive the Lightning Address nostr identity from the default Bitcoin wallet.
/// Returns null if no default wallet is available.
Future<NostrIdentity?> deriveNostrIdentityForLightningAddress({
  required WalletRepository walletRepository,
  required SeedRepository seedRepository,
}) async {
  final wallets = await walletRepository.getWallets(
    onlyDefaults: true,
    onlyBitcoin: true,
  );
  if (wallets.isEmpty) return null;
  final seed = await seedRepository.get(wallets.first.masterFingerprint);
  final xprv = Bip32Derivation.getXprvFromSeed(
    seed.bytes,
    wallets.first.network,
  );
  return NostrIdentity.derive(
    xprvBase58: xprv,
    identity: lightningAddressNostrIdentity,
    account: lightningAddressNostrAccount,
  );
}
