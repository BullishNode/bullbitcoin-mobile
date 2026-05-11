import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';

class ClearLightningAddressNostrProfileUsecase {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final NostrPublishPort _nostrPublish;

  ClearLightningAddressNostrProfileUsecase({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required NostrPublishPort nostrPublish,
  }) : _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _nostrPublish = nostrPublish;

  Future<void> execute() async {
    try {
      final xprv = await deriveDefaultWalletXprv(
        walletRepository: _walletRepository,
        seedRepository: _seedRepository,
      );
      final handle = deriveNostrHandleFromXprvForLightningAddress(xprv);
      await _nostrPublish.clearProfile(handle: handle);
    } on LightningAddressNostrPublishFailedException {
      rethrow;
    } catch (e) {
      throw LightningAddressNostrPublishFailedException(e.toString());
    }
  }
}
