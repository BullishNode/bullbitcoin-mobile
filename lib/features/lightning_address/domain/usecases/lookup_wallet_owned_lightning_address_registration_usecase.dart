import 'package:bb_mobile/features/lightning_address/application/ports/lightning_address_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_models.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';

class LookupWalletOwnedLightningAddressRegistrationUsecase {
  final LightningAddressDefaultWalletXprvPort _defaultWalletXprv;
  final LookupLightningAddressRegistrationUsecase _lookupRegistration;
  final NostrIdentityFacade _nostrIdentity;

  const LookupWalletOwnedLightningAddressRegistrationUsecase({
    required LightningAddressDefaultWalletXprvPort defaultWalletXprv,
    required LookupLightningAddressRegistrationUsecase lookupRegistration,
    required NostrIdentityFacade nostrIdentity,
  }) : _defaultWalletXprv = defaultWalletXprv,
       _lookupRegistration = lookupRegistration,
       _nostrIdentity = nostrIdentity;

  Future<LightningAddressStatus> execute() async {
    final xprvBase58 = await _deriveDefaultWalletXprv();
    final npubHex = _nostrIdentity.deriveBullnymServerAuthPublicKeyFromXprv(
      xprvBase58,
    );
    return _lookupRegistration.execute(npubHex: npubHex);
  }

  Future<String> _deriveDefaultWalletXprv() async {
    try {
      return await _defaultWalletXprv.deriveDefaultWalletXprv();
    } on LightningAddressException {
      rethrow;
    } catch (e) {
      throw LightningAddressException.localPreparationFailed(
        code: e.runtimeType.toString(),
        retryable: true,
      );
    }
  }
}
