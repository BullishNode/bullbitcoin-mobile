import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/shared/get_paid_nostr_identity.dart';

class PaymentPageIdentityDatasource implements PaymentPageIdentityPort {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  const PaymentPageIdentityDatasource({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  }) : _walletRepository = walletRepository,
       _seedRepository = seedRepository;

  @override
  Future<NostrKeychainHandle> getSigningHandle() async {
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) {
      throw const PaymentPageIdentityUnavailableError(
        'No default Bitcoin wallet found',
      );
    }

    final defaultWallet = wallets.first;
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
