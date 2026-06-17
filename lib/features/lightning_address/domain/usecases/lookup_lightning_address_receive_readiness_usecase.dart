import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_models.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_wallet_owned_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/prepare_lightning_address_wallet_usecase.dart';

class LightningAddressReceiveReadiness {
  final LightningAddressStatus registration;
  final bool receiveReady;
  final bool localSetupFailed;

  const LightningAddressReceiveReadiness({
    required this.registration,
    required this.receiveReady,
    this.localSetupFailed = false,
  });
}

class LookupLightningAddressReceiveReadinessUsecase {
  final LookupWalletOwnedLightningAddressRegistrationUsecase
  _lookupRegistration;
  final PrepareLightningAddressWalletUsecase _prepareWallet;

  const LookupLightningAddressReceiveReadinessUsecase({
    required this._lookupRegistration,
    required this._prepareWallet,
  });

  Future<LightningAddressReceiveReadiness> execute() async {
    final registration = await _lookupRegistration.execute();
    if (!registration.active) {
      return LightningAddressReceiveReadiness(
        registration: registration,
        receiveReady: false,
      );
    }

    try {
      await _prepareWallet.execute();
    } on LightningAddressException catch (e) {
      if (e.kind != LightningAddressErrorKind.localPreparationFailed) {
        rethrow;
      }
      return LightningAddressReceiveReadiness(
        registration: registration,
        receiveReady: false,
        localSetupFailed: true,
      );
    }

    return LightningAddressReceiveReadiness(
      registration: registration,
      receiveReady: true,
    );
  }
}
