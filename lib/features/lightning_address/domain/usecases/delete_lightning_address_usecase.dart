import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:flutter/foundation.dart';

class DeleteLightningAddressUsecase {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final PayServicePort _payService;

  DeleteLightningAddressUsecase({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required PayServicePort payService,
  })  : _walletRepository = walletRepository,
        _seedRepository = seedRepository,
        _payService = payService;

  Future<void> execute() async {
    final xprv = await _deriveXprv();
    final nostr = NostrIdentity.derive(
      xprvBase58: xprv,
      identity: lightningAddressNostrIdentity,
      account: lightningAddressNostrAccount,
    );

    final signature = nostr.signSchnorr('delete'.codeUnits);

    try {
      await _payService.deleteRegistration(
        npubHex: nostr.npubHex,
        signatureHex: signature,
      );

      // Clear NIP-05 profile on nostr relays (best-effort)
      try {
        await NostrRelayClient.clearProfile(
          privateKeyHex: nostr.nsecHex,
        );
      } catch (e) {
        debugPrint('Nostr relay profile clear failed: $e');
      }
    } on PayServiceException catch (e) {
      throw LightningAddressRegistrationException(e.message);
    }
  }

  Future<String> _deriveXprv() async {
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) throw LightningAddressNoDefaultWalletException();
    final defaultWallet = wallets.first;

    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    return Bip32Derivation.getXprvFromSeed(
      seed.bytes,
      defaultWallet.network,
    );
  }
}
