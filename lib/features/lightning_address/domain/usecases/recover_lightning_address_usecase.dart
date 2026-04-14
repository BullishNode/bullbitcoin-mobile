import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:flutter/foundation.dart';

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

    final lookup = await _payService.lookupByNpub(nostr.npubHex);
    if (lookup == null || !lookup.active) return null;

    final existing = await _getWallet.execute(environment: environment);
    if (existing == null) {
      try {
        await _createWallet.execute(environment: environment);
      } on LightningAddressWalletAlreadyExistsException {
        // Race condition — wallet created between check and create
      }
    }

    final address = '${lookup.nym}@$lightningAddressDomain';
    await _payService.storeAddress(address);

    debugPrint('Lightning Address recovered: $address');
    return address;
  }
}
