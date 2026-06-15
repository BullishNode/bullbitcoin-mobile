import 'package:bb_mobile/features/lightning_address/domain/lightning_address_models.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_receive_readiness_usecase.dart';

export 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart'
    hide
        WalletOwnedLightningAddressActivationException,
        WalletOwnedLightningAddressActivationFailurePhase;
export 'package:bb_mobile/features/lightning_address/domain/lightning_address_models.dart';
export 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet.dart'
    show PreparedLightningAddressWallet;
export 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet_registration.dart'
    show WalletOwnedLightningAddressRegistration;
export 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_receive_readiness_usecase.dart'
    show LightningAddressReceiveReadiness;

class LightningAddressFacade {
  final Future<PreparedLightningAddressWallet> Function() _prepareWallet;
  final Future<LightningAddressStatus> Function({required String npubHex})
  _lookupRegistration;
  final Future<WalletOwnedLightningAddressRegistration> Function({
    required String nym,
  })
  _registerWalletOwned;
  final Future<LightningAddressStatus> Function()
  _lookupWalletOwnedRegistration;
  final Future<LightningAddressReceiveReadiness> Function()
  _lookupReceiveReadiness;

  const LightningAddressFacade({
    required Future<PreparedLightningAddressWallet> Function() prepareWallet,
    required Future<LightningAddressStatus> Function({required String npubHex})
    lookupRegistration,
    required Future<WalletOwnedLightningAddressRegistration> Function({
      required String nym,
    })
    registerWalletOwned,
    required Future<LightningAddressStatus> Function()
    lookupWalletOwnedRegistration,
    required Future<LightningAddressReceiveReadiness> Function()
    lookupReceiveReadiness,
  }) : _prepareWallet = prepareWallet,
       _lookupRegistration = lookupRegistration,
       _registerWalletOwned = registerWalletOwned,
       _lookupWalletOwnedRegistration = lookupWalletOwnedRegistration,
       _lookupReceiveReadiness = lookupReceiveReadiness;

  Future<PreparedLightningAddressWallet> prepareWallet() {
    return _prepareWallet();
  }

  Future<WalletOwnedLightningAddressRegistration> registerWalletOwned({
    required String nym,
  }) {
    return _registerWalletOwned(nym: nym);
  }

  Future<LightningAddressStatus> lookupWalletOwnedRegistration() {
    return _lookupWalletOwnedRegistration();
  }

  Future<LightningAddressStatus> lookupRegistration({required String npubHex}) {
    return _lookupRegistration(npubHex: npubHex);
  }

  Future<LightningAddressReceiveReadiness> lookupReceiveReadiness() {
    return _lookupReceiveReadiness();
  }
}
