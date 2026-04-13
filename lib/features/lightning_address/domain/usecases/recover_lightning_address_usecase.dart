import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/pay_service_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:flutter/foundation.dart';

/// Checks the pay service for an existing Lightning Address registration
/// and restores the wallet + local state if found.
/// Intended to run once after wallet recovery/import.
class RecoverLightningAddressUsecase {
  final GetLightningAddressWalletUsecase _getWallet;
  final CreateLightningAddressWalletUsecase _createWallet;
  final PayServiceDatasource _payService;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  RecoverLightningAddressUsecase({
    required GetLightningAddressWalletUsecase getWallet,
    required CreateLightningAddressWalletUsecase createWallet,
    required PayServiceDatasource payService,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  })  : _getWallet = getWallet,
        _createWallet = createWallet,
        _payService = payService,
        _walletRepository = walletRepository,
        _seedRepository = seedRepository;

  /// Returns the recovered lightning address, or null if no registration found.
  Future<String?> execute({required Environment environment}) async {
    // Already have a stored address — nothing to recover
    final stored = await _payService.getStoredAddress();
    if (stored != null) return null;

    // Derive Nostr identity and check the server
    final nostr = await deriveNostrIdentityForLightningAddress(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
    );
    if (nostr == null) return null;

    final lookup = await _payService.lookupByNpub(nostr.npubHex);
    if (lookup == null || !lookup.active) return null;

    // Server knows this npub — create the wallet if it doesn't exist
    final existing = await _getWallet.execute(environment: environment);
    if (existing == null) {
      try {
        await _createWallet.execute(environment: environment);
      } catch (_) {
        // Wallet might already exist from a race — that's fine
      }
    }

    // Store the address locally
    final address = '${lookup.nym}@$lightningAddressDomain';
    await _payService.storeAddress(address);

    debugPrint('Lightning Address recovered: $address');
    return address;
  }
}
