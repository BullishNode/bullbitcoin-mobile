import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';

/// Force the user's Nostr kind:0 profile to match the canonical bullpay
/// state. Idempotent — the user can invoke this any time from the settings
/// screen.
///
/// Used as the manual retry path when the initial publish during register or
/// delete reaches zero relays. The bullpay server is the source of truth:
/// `lookupByNpub` returns whether the npub currently has an active nym; the
/// profile is then either re-asserted (Active) or cleared (Inactive / no
/// row).
class RepublishNostrProfileUsecase {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final PayServicePort _payService;
  final NostrPublishPort _nostrPublish;

  RepublishNostrProfileUsecase({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required PayServicePort payService,
    required NostrPublishPort nostrPublish,
  })  : _walletRepository = walletRepository,
        _seedRepository = seedRepository,
        _payService = payService,
        _nostrPublish = nostrPublish;

  Future<void> execute() async {
    final xprv = await deriveDefaultWalletXprv(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
    );
    final nostr = NostrIdentity.derive(
      xprvBase58: xprv,
      identity: lightningAddressNostrIdentity,
      account: lightningAddressNostrAccount,
    );

    final lookup = await _payService.lookupByNpub(nostr.npubHex);

    try {
      switch (lookup) {
        case ActiveLookupResult(:final nym):
          final address = '$nym@$lightningAddressDomain';
          await nostr.withPrivateKeyHex(
            (nsec) => _nostrPublish.publishProfile(
              privateKeyHex: nsec,
              name: nym,
              nip05: address,
              lud16: address,
            ),
          );
        case InactiveLookupResult() || null:
          await nostr.withPrivateKeyHex(
            (nsec) => _nostrPublish.clearProfile(privateKeyHex: nsec),
          );
      }
    } on NostrPublishFailedException catch (e) {
      throw LightningAddressNostrPublishFailedException(e.message);
    }
  }
}
