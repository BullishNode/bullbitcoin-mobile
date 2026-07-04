import 'package:bb_mobile/features/lightning_address/domain/lightning_address_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_nym_validation.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/prepare_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';

class RegisterWalletOwnedLightningAddressUsecase {
  final LightningAddressDefaultWalletXprvPort _defaultWalletXprv;
  final PrepareLightningAddressWalletUsecase _prepareWallet;
  final RegisterLightningAddressUsecase _register;
  final GetPaidSettingsFacade _getPaidSettings;

  const RegisterWalletOwnedLightningAddressUsecase({
    required this._defaultWalletXprv,
    required this._prepareWallet,
    required this._register,
    required this._getPaidSettings,
  });

  Future<WalletOwnedLightningAddressRegistration> execute({
    required String nym,
  }) async {
    validateLightningAddressNym(nym);

    var walletPrepared = false;
    try {
      final xprvBase58 = await _deriveDefaultWalletXprv();
      final preparedWallet = await _prepareLightningAddressWallet();
      // The manifest record is durable once prepare returns — even when the
      // server registration then fails, funds can arrive at the wallet — so the
      // backup must publish. Post-commitment (AD-3): the finally publishes
      // best-effort and never changes this flow's outcome.
      walletPrepared = true;
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
    } finally {
      if (walletPrepared) {
        await _getPaidSettings.publishBackupSnapshotIfEnabled();
      }
    }
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
