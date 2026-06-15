import 'package:bb_mobile/features/lightning_address/domain/lightning_address_models.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_wallet_owned_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/prepare_lightning_address_wallet_usecase.dart';

class LightningAddressReceiveReadiness {
  final LightningAddressStatus registration;
  final bool receiveReady;

  const LightningAddressReceiveReadiness({
    required this.registration,
    required this.receiveReady,
  });
}

class LookupLightningAddressReceiveReadinessUsecase {
  final LookupWalletOwnedLightningAddressRegistrationUsecase
  _lookupRegistration;
  final PrepareLightningAddressWalletUsecase _prepareWallet;

  const LookupLightningAddressReceiveReadinessUsecase({
    required LookupWalletOwnedLightningAddressRegistrationUsecase
    lookupRegistration,
    required PrepareLightningAddressWalletUsecase prepareWallet,
  }) : _lookupRegistration = lookupRegistration,
       _prepareWallet = prepareWallet;

  Future<LightningAddressReceiveReadiness> execute() async {
    final registration = await _lookupRegistration.execute();
    if (!registration.active) {
      return LightningAddressReceiveReadiness(
        registration: registration,
        receiveReady: false,
      );
    }

    await _prepareWallet.execute();
    return LightningAddressReceiveReadiness(
      registration: registration,
      receiveReady: true,
    );
  }
}
