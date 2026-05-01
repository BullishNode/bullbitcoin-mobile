import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';

class RecoverLightningAddressUsecase {
  final GetLightningAddressWalletUsecase _getWallet;
  final CreateLightningAddressWalletUsecase _createWallet;
  final PayServicePort _payService;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  RecoverLightningAddressUsecase({
    required GetLightningAddressWalletUsecase getWallet,
    required CreateLightningAddressWalletUsecase createWallet,
    required PayServicePort payService,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  })  : _getWallet = getWallet,
        _createWallet = createWallet,
        _payService = payService,
        _walletRepository = walletRepository,
        _seedRepository = seedRepository;

  Future<String?> execute({required Environment environment}) async {
    final stored = await _payService.getStoredAddress();
    if (stored != null) return null;

    final nostr = await deriveNostrIdentityForLightningAddress(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
    );
    if (nostr == null) return null;

    final ({String nym, bool active})? lookup;
    try {
      lookup = await _payService.lookupByNpub(nostr.npubHex);
    } on PayServiceException {
      // Transient server/network failure — don't mark recovery complete so
      // it'll retry on the next launch.
      return null;
    }
    if (lookup == null || !lookup.active) return null;

    final existing = await _getWallet.execute(
      environment: environment,
    );
    if (existing == null) {
      await _createWallet.execute(environment: environment);
    }

    final address = '${lookup.nym}@$lightningAddressDomain';
    await _payService.storeAddress(address);

    return address;
  }
}
