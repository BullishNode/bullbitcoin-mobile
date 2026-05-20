import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';

class RecoverLightningAddressUsecase {
  final ExternalReceiveWalletsFacade _externalReceiveWallets;
  final PayServicePort _payService;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  RecoverLightningAddressUsecase({
    required ExternalReceiveWalletsFacade externalReceiveWallets,
    required PayServicePort payService,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  }) : _externalReceiveWallets = externalReceiveWallets,
       _payService = payService,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository;

  Future<String?> execute({required Environment environment}) async {
    final stored = await _payService.getStoredAddress();
    if (stored != null) return null;

    final nostr = await deriveBullnymServerAuthIdentityForLightningAddress(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
      environment: environment,
    );
    if (nostr == null) return null;

    final lookup = await _safeLookup(nostr.npubHex);
    // Recovery only auto-restores active registrations; an inactive row
    // means the user previously deactivated and we don't want to silently
    // re-activate. The settings flow surfaces the previous-addresses banner.
    if (lookup is! ActiveLookupResult) return null;

    final existing = await _externalReceiveWallets.get(
      environment: environment,
      purpose: ExternalReceiveWalletPurpose.lightningAddress,
    );
    if (existing == null) {
      await _externalReceiveWallets.create(
        environment: environment,
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
      );
    }

    final address = '${lookup.nym}@$lightningAddressDomain';
    await _payService.storeAddress(address);

    return address;
  }

  Future<LookupResult?> _safeLookup(String npubHex) async {
    try {
      return await _payService.lookupByNpub(npubHex);
    } on PayServiceException {
      // Transient server/network failure — don't mark recovery complete so
      // the next launch retries.
      return null;
    }
  }
}
