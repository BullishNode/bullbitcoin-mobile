import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_v1_signing.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:flutter/foundation.dart';

class DeleteLightningAddressUsecase {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final PayServicePort _payService;
  final NostrPublishPort _nostrPublish;

  DeleteLightningAddressUsecase({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required PayServicePort payService,
    required NostrPublishPort nostrPublish,
  })  : _walletRepository = walletRepository,
        _seedRepository = seedRepository,
        _payService = payService,
        _nostrPublish = nostrPublish;

  Future<NymQuota> execute() async {
    final xprv = await deriveDefaultWalletXprv(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
    );
    final nostr = NostrIdentity.derive(
      xprvBase58: xprv,
      identity: lightningAddressNostrIdentity,
      account: lightningAddressNostrAccount,
    );

    final timestampSecs = currentUnixTimestampSecs();
    final messageBytes = buildLaV1Message(
      action: 'delete',
      npubHex: nostr.npubHex,
      payloadFields: const [],
      timestampSecs: timestampSecs,
    );
    final signature = nostr.signSchnorr(messageBytes);

    try {
      final quota = await _payService.deleteRegistration(
        npubHex: nostr.npubHex,
        signatureHex: signature,
        timestampSecs: timestampSecs,
      );

      // Clear NIP-05 profile on nostr relays (best-effort)
      try {
        await nostr.withPrivateKeyHex(
          (nsec) => _nostrPublish.clearProfile(privateKeyHex: nsec),
        );
      } catch (e) {
        debugPrint('Nostr relay profile clear failed: $e');
      }

      return quota;
    } on PayServiceException catch (e) {
      throw LightningAddressRegistrationException(e.message);
    }
  }

}
