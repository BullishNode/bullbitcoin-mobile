import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';

class LookupLightningAddressStatusUsecase {
  final PayServicePort _payService;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  LookupLightningAddressStatusUsecase({
    required PayServicePort payService,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  }) : _payService = payService,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository;

  Future<LookupResult?> execute() async {
    final nostr = await deriveBullnymServerAuthIdentityForLightningAddress(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
    );
    if (nostr == null) return null;
    return _payService.lookupByNpub(nostr.npubHex);
  }
}
