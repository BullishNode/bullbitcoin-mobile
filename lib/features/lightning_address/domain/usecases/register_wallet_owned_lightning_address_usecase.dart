import 'package:bb_mobile/features/lightning_address/application/ports/lightning_address_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_models.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_nym_validation.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/prepare_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';

class RegisterWalletOwnedLightningAddressCommand {
  final String nym;

  const RegisterWalletOwnedLightningAddressCommand({required this.nym});
}

class WalletOwnedLightningAddressRegistration {
  final LightningAddressRegistration registration;
  final String walletId;
  final bool walletCreated;

  const WalletOwnedLightningAddressRegistration({
    required this.registration,
    required this.walletId,
    required this.walletCreated,
  });
}

enum WalletOwnedLightningAddressRegistrationFailurePhase {
  localPreparation,
  registrationSubmission,
}

bool isLightningAddressRegistrationSubmissionUncertain(
  LightningAddressException error,
) {
  return switch (error.kind) {
    LightningAddressErrorKind.network ||
    LightningAddressErrorKind.timeout ||
    LightningAddressErrorKind.invalidServerResponse => true,
    LightningAddressErrorKind.invalidNym ||
    LightningAddressErrorKind.serverRejectedRequest ||
    LightningAddressErrorKind.signingFailed ||
    LightningAddressErrorKind.localPreparationFailed ||
    LightningAddressErrorKind.unexpected => false,
  };
}

class WalletOwnedLightningAddressRegistrationException implements Exception {
  final WalletOwnedLightningAddressRegistrationFailurePhase phase;
  final LightningAddressException cause;
  final String? walletId;
  final bool walletCreated;
  final bool submissionMayBeUncertain;

  const WalletOwnedLightningAddressRegistrationException.localPreparation({
    required this.cause,
  }) : phase =
           WalletOwnedLightningAddressRegistrationFailurePhase.localPreparation,
       walletId = null,
       walletCreated = false,
       submissionMayBeUncertain = false;

  WalletOwnedLightningAddressRegistrationException.registrationSubmission({
    required this.cause,
    required this.walletId,
    required this.walletCreated,
  }) : phase = WalletOwnedLightningAddressRegistrationFailurePhase
           .registrationSubmission,
       submissionMayBeUncertain =
           isLightningAddressRegistrationSubmissionUncertain(cause);

  bool get descriptorMayHaveBeenSubmitted =>
      phase ==
      WalletOwnedLightningAddressRegistrationFailurePhase
          .registrationSubmission;

  @override
  String toString() {
    return 'WalletOwnedLightningAddressRegistrationException('
        'phase: $phase, cause: $cause)';
  }
}

class RegisterWalletOwnedLightningAddressUsecase {
  final LightningAddressDefaultWalletXprvPort _defaultWalletXprv;
  final PrepareLightningAddressWalletUsecase _prepareWallet;
  final RegisterLightningAddressUsecase _register;

  const RegisterWalletOwnedLightningAddressUsecase({
    required LightningAddressDefaultWalletXprvPort defaultWalletXprv,
    required PrepareLightningAddressWalletUsecase prepareWallet,
    required RegisterLightningAddressUsecase register,
  }) : _defaultWalletXprv = defaultWalletXprv,
       _prepareWallet = prepareWallet,
       _register = register;

  Future<WalletOwnedLightningAddressRegistration> execute(
    RegisterWalletOwnedLightningAddressCommand command,
  ) async {
    validateLightningAddressNym(command.nym);

    final xprvBase58 = await _deriveDefaultWalletXprv();
    final preparedWallet = await _prepareLightningAddressWallet();
    late final LightningAddressRegistration registration;
    try {
      registration = await _register.execute(
        xprvBase58: xprvBase58,
        nym: command.nym,
        ctDescriptor: preparedWallet.ctDescriptor,
      );
    } on LightningAddressException catch (e) {
      throw WalletOwnedLightningAddressRegistrationException.registrationSubmission(
        cause: e,
        walletId: preparedWallet.walletId,
        walletCreated: preparedWallet.created,
      );
    }

    return WalletOwnedLightningAddressRegistration(
      registration: registration,
      walletId: preparedWallet.walletId,
      walletCreated: preparedWallet.created,
    );
  }

  Future<String> _deriveDefaultWalletXprv() async {
    try {
      return await _defaultWalletXprv.deriveDefaultWalletXprv();
    } on LightningAddressException catch (e) {
      throw WalletOwnedLightningAddressRegistrationException.localPreparation(
        cause: e,
      );
    } catch (e) {
      throw WalletOwnedLightningAddressRegistrationException.localPreparation(
        cause: LightningAddressException.localPreparationFailed(
          code: e.runtimeType.toString(),
          retryable: true,
        ),
      );
    }
  }

  Future<PreparedLightningAddressWallet>
  _prepareLightningAddressWallet() async {
    try {
      return await _prepareWallet.execute();
    } on LightningAddressException catch (e) {
      throw WalletOwnedLightningAddressRegistrationException.localPreparation(
        cause: e,
      );
    } catch (e) {
      throw WalletOwnedLightningAddressRegistrationException.localPreparation(
        cause: LightningAddressException.localPreparationFailed(
          code: e.runtimeType.toString(),
          retryable: true,
        ),
      );
    }
  }
}
