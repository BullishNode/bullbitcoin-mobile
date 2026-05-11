import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';

class RegisterLightningAddressUsecase {
  final CreateLightningAddressWalletUsecase _createWallet;
  final GetLightningAddressWalletUsecase _getWallet;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final PayServicePort _payService;

  RegisterLightningAddressUsecase({
    required CreateLightningAddressWalletUsecase createWallet,
    required GetLightningAddressWalletUsecase getWallet,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required PayServicePort payService,
  }) : _createWallet = createWallet,
       _getWallet = getWallet,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _payService = payService;

  Future<({String address, NymQuota quota})> execute({
    required String nym,
    required Environment environment,
  }) async {
    var wallet = await _getWallet.execute(environment: environment);
    wallet ??= await _createWallet.execute(environment: environment);

    final xprv = await deriveDefaultWalletXprv(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
    );
    final handle = deriveNostrHandleFromXprvForLightningAddress(xprv);

    final ctDescriptor = wallet.externalPublicDescriptor;

    try {
      return await _payService.register(
        nym: nym,
        ctDescriptor: ctDescriptor,
        handle: handle,
      );
    } on PayServiceException catch (e) {
      throw LightningAddressRegistrationException(e.message);
    }
  }
}
