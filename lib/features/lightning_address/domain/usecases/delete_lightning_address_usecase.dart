import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';

class DeleteLightningAddressUsecase {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final PayServicePort _payService;

  DeleteLightningAddressUsecase({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required PayServicePort payService,
  }) : _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _payService = payService;

  Future<NymQuota> execute({required String nym}) async {
    final xprv = await deriveDefaultWalletXprv(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
    );
    final handle = deriveNostrHandleFromXprvForLightningAddress(xprv);

    try {
      return await _payService.deleteRegistration(nym: nym, handle: handle);
    } on PayServiceException catch (e) {
      throw LightningAddressRegistrationException(e.message);
    }
  }
}
