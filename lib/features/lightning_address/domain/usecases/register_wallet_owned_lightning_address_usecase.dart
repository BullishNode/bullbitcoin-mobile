import 'package:bb_mobile/features/lightning_address/domain/lightning_address_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_nym_validation.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/prepare_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';

class RegisterWalletOwnedLightningAddressUsecase {
  final LightningAddressDefaultWalletXprvPort _defaultWalletXprv;
  final PrepareLightningAddressWalletUsecase _prepareWallet;
  final RegisterLightningAddressUsecase _register;

  const RegisterWalletOwnedLightningAddressUsecase({
    required this._defaultWalletXprv,
    required this._prepareWallet,
    required this._register,
  });

  Future<WalletOwnedLightningAddressRegistration> execute({
    required String nym,
  }) {
    return _execute(nym: nym, recordAsRecovery: false);
  }

  Future<WalletOwnedLightningAddressRegistration> executeFromRecovery({
    required String nym,
  }) {
    return _execute(nym: nym, recordAsRecovery: true);
  }

  Future<WalletOwnedLightningAddressRegistration> _execute({
    required String nym,
    required bool recordAsRecovery,
  }) async {
    validateLightningAddressNym(nym);

    final xprvBase58 = await _deriveDefaultWalletXprv();
    final preparedWallet = await _prepareLightningAddressWallet(
      recordAsRecovery: recordAsRecovery,
    );
    late final LightningAddressRegistration registration;
    try {
      registration = await _register.execute(
        xprvBase58: xprvBase58,
        nym: nym,
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

  Future<PreparedLightningAddressWallet> _prepareLightningAddressWallet({
    required bool recordAsRecovery,
  }) async {
    try {
      return await _prepareWallet.execute(recordAsRecovery: recordAsRecovery);
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
