import 'package:bb_mobile/features/bullnym/domain/bullnym_auth_signer.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration_liveness.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet_registration.dart';

export 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart'
    hide
        WalletOwnedLightningAddressActivationException,
        WalletOwnedLightningAddressActivationFailurePhase;
export 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
export 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration_liveness.dart';
export 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet.dart'
    show PreparedLightningAddressWallet;
export 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet_registration.dart'
    show WalletOwnedLightningAddressRegistration;

class LightningAddressFacade {
  final Future<PreparedLightningAddressWallet> Function()
  _prepareWalletCallback;
  final Future<LightningAddressStatus> Function({
    required BullnymAuthSigner signer,
  })
  _lookupRegistrationCallback;
  final Future<WalletOwnedLightningAddressRegistration> Function({
    required String nym,
  })
  _registerWalletOwnedCallback;
  final Future<LightningAddressStatus> Function()
  _lookupWalletOwnedRegistrationCallback;
  final Future<LightningAddressHealOutcome> Function({
    DateTime? deadline,
    bool allowReregister,
  })
  _ensureRegistrationLiveCallback;

  const LightningAddressFacade({
    required Future<PreparedLightningAddressWallet> Function() prepareWallet,
    required Future<LightningAddressStatus> Function({
      required BullnymAuthSigner signer,
    })
    lookupRegistration,
    required Future<WalletOwnedLightningAddressRegistration> Function({
      required String nym,
    })
    registerWalletOwned,
    required Future<LightningAddressStatus> Function()
    lookupWalletOwnedRegistration,
    required Future<LightningAddressHealOutcome> Function({
      DateTime? deadline,
      bool allowReregister,
    })
    ensureRegistrationLive,
  }) : _prepareWalletCallback = prepareWallet,
       _lookupRegistrationCallback = lookupRegistration,
       _registerWalletOwnedCallback = registerWalletOwned,
       _lookupWalletOwnedRegistrationCallback = lookupWalletOwnedRegistration,
       _ensureRegistrationLiveCallback = ensureRegistrationLive;

  Future<PreparedLightningAddressWallet> prepareWallet() {
    return _prepareWalletCallback();
  }

  Future<WalletOwnedLightningAddressRegistration> registerWalletOwned({
    required String nym,
  }) {
    return _registerWalletOwnedCallback(nym: nym);
  }

  Future<LightningAddressStatus> lookupWalletOwnedRegistration() {
    return _lookupWalletOwnedRegistrationCallback();
  }

  Future<LightningAddressStatus> lookupRegistration({
    required BullnymAuthSigner signer,
  }) {
    return _lookupRegistrationCallback(signer: signer);
  }

  Future<LightningAddressHealOutcome> ensureRegistrationLive({
    DateTime? deadline,
    bool allowReregister = true,
  }) {
    return _ensureRegistrationLiveCallback(
      deadline: deadline,
      allowReregister: allowReregister,
    );
  }
}
