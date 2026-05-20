import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';

class RegisterLightningAddressUsecase {
  final ExternalReceiveWalletsFacade _externalReceiveWallets;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final PayServicePort _payService;

  RegisterLightningAddressUsecase({
    required ExternalReceiveWalletsFacade externalReceiveWallets,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required PayServicePort payService,
  }) : _externalReceiveWallets = externalReceiveWallets,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _payService = payService;

  Future<({String address, NymQuota quota})> execute({
    required String nym,
    required Environment environment,
  }) async {
    var wallet = await _externalReceiveWallets.get(
      environment: environment,
      purpose: ExternalReceiveWalletPurpose.lightningAddress,
    );
    wallet ??= await _externalReceiveWallets.create(
      environment: environment,
      purpose: ExternalReceiveWalletPurpose.lightningAddress,
    );

    final xprv = await deriveDefaultWalletXprv(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
      environment: environment,
    );
    final authHandle = deriveBullnymServerAuthHandleFromXprvForLightningAddress(
      xprv,
    );
    final verificationHandle =
        deriveNip05VerificationHandleFromXprvForLightningAddress(xprv);

    final ctDescriptor = wallet.externalPublicDescriptor;

    try {
      return await _payService.register(
        nym: nym,
        ctDescriptor: ctDescriptor,
        authHandle: authHandle,
        verificationNpubHex: verificationHandle.publicKeyHex,
      );
    } on PayServiceException catch (e) {
      throw LightningAddressRegistrationException(e.message);
    }
  }
}
