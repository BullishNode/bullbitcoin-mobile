import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_models.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_wallet_owned_lightning_address_usecase.dart';

class WalletOwnedLightningAddressActivation {
  final LightningAddressRegistration registration;
  final bool walletCreated;

  const WalletOwnedLightningAddressActivation({
    required this.registration,
    required this.walletCreated,
  });
}

enum WalletOwnedLightningAddressActivationFailurePhase {
  localPreparation,
  registrationSubmission,
}

class WalletOwnedLightningAddressActivationException implements Exception {
  final WalletOwnedLightningAddressActivationFailurePhase phase;
  final LightningAddressException cause;
  final bool walletCreated;
  final bool submissionMayBeUncertain;

  const WalletOwnedLightningAddressActivationException({
    required this.phase,
    required this.cause,
    required this.walletCreated,
    required this.submissionMayBeUncertain,
  });

  @override
  String toString() {
    return 'WalletOwnedLightningAddressActivationException('
        'phase: $phase, cause: $cause)';
  }
}

class ActivateWalletOwnedLightningAddressUsecase {
  final RegisterWalletOwnedLightningAddressUsecase _registerWalletOwned;

  const ActivateWalletOwnedLightningAddressUsecase({
    required RegisterWalletOwnedLightningAddressUsecase registerWalletOwned,
  }) : _registerWalletOwned = registerWalletOwned;

  Future<WalletOwnedLightningAddressActivation> execute({
    required String nym,
  }) async {
    try {
      final result = await _registerWalletOwned.execute(nym: nym);
      return WalletOwnedLightningAddressActivation(
        registration: result.registration,
        walletCreated: result.walletCreated,
      );
    } on WalletOwnedLightningAddressRegistrationException catch (e) {
      throw WalletOwnedLightningAddressActivationException(
        phase: switch (e.phase) {
          WalletOwnedLightningAddressRegistrationFailurePhase
              .localPreparation =>
            WalletOwnedLightningAddressActivationFailurePhase.localPreparation,
          WalletOwnedLightningAddressRegistrationFailurePhase
              .registrationSubmission =>
            WalletOwnedLightningAddressActivationFailurePhase
                .registrationSubmission,
        },
        cause: e.cause,
        walletCreated: e.walletCreated,
        submissionMayBeUncertain: e.submissionMayBeUncertain,
      );
    }
  }
}
