import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/lightning_address/application/application_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_models.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';

class LookupLightningAddressRegistrationUsecase {
  final BullnymFacade _bullnym;
  final NostrIdentityFacade _nostrIdentity;

  const LookupLightningAddressRegistrationUsecase({
    required BullnymFacade bullnym,
    required NostrIdentityFacade nostrIdentity,
  }) : _bullnym = bullnym,
       _nostrIdentity = nostrIdentity;

  Future<LightningAddressStatus> execute({required String xprvBase58}) async {
    try {
      final handle = _nostrIdentity.deriveBullnymServerAuthHandleFromXprv(
        xprvBase58,
      );
      final result = await _bullnym.lookupRegistration(
        npubHex: handle.publicKeyHex,
      );
      return result.active
          ? LightningAddressStatus.active(nym: result.nym)
          : LightningAddressStatus.inactive(nym: result.nym);
    } on BullnymException catch (e) {
      throw LightningAddressException.fromBullnym(e);
    } catch (e) {
      throw LightningAddressException.unexpected(e);
    }
  }
}
