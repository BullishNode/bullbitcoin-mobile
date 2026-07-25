import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/pos/domain/pos_error.dart';
import 'package:bb_mobile/features/pos/domain/pos_terminal.dart';
import 'package:bb_mobile/features/pos/domain/pos_validation.dart';
import 'package:bb_mobile/features/pos/domain/usecases/prepare_pos_wallet_usecase.dart';
import 'package:bb_mobile/features/pos/domain/usecases/resolve_pos_identity_usecase.dart';

/// The Point of Sale provision/edit orchestrator (§3.6/§4.20).
///
/// Order: validate locally → resolve nym + signer → prepare wallet 103 (ALWAYS,
/// so the 103 descriptor is ALWAYS sent - KR-1) → signed PUT with kind=pos,
/// label in the `header` slot, description/socials empty, enabled=true.
/// Preparing a new wallet commits its keychain-manifest entry; the wallet-backup
/// coordinator observes that commit independently. Unlike the page, the server
/// has NO empty-descriptor fallback for kind=pos, so an empty descriptor both
/// cannot be constructed here (the `EmptyPosDescriptor` guard) AND is
/// hard-rejected by the server: POS sales settle to 103, never 101/102.
class ProvisionPosUsecase {
  final ResolvePosIdentityUsecase _resolveIdentity;
  final PreparePosWalletUsecase _prepareWallet;
  final BullnymFacade _bullnym;
  final String _terminalBaseUrl;

  const ProvisionPosUsecase({
    required this._resolveIdentity,
    required this._prepareWallet,
    required this._bullnym,
    required this._terminalBaseUrl,
  });

  Future<PosTerminal> execute({
    required String label,
    required String displayCurrency,
  }) async {
    // Local pre-filter (UX; the server remains the authority). A validation
    // failure never touches the wire or the wallet.
    PosProvisionCommand(
      label: label,
      displayCurrency: displayCurrency,
    ).validate();

    final ResolvedPosIdentity identity;
    final String ctDescriptor;
    try {
      identity = await _resolveIdentity.execute();
      final preparedWallet = await _prepareWallet.execute();
      // KR-1: the descriptor is ALWAYS the prepared 103 wallet's non-empty
      // external public descriptor - never empty, never absent. This runtime
      // guard makes the invariant explicit and fails BEFORE signing/wire so
      // POS sales can never route anywhere but wallet 103.
      ctDescriptor = preparedWallet.ctDescriptor;
      if (ctDescriptor.isEmpty) {
        throw const PosException.localPreparationFailed(
          code: 'EmptyPosDescriptor',
          retryable: false,
        );
      }
    } on PosException catch (e) {
      throw PosProvisionException.localPreparation(cause: e);
    }

    try {
      final view = await _bullnym.saveDonationPage(
        signer: identity.signer,
        nym: identity.nym,
        ctDescriptor: ctDescriptor,
        header: label,
        description: '',
        displayCurrency: displayCurrency,
        website: '',
        twitter: '',
        instagram: '',
        enabled: true,
        kind: bullnymDonationPageKindPos,
      );
      return PosTerminal.fromBullnym(view, baseUrl: _terminalBaseUrl);
    } on BullnymException catch (e) {
      throw PosProvisionException.submission(
        cause: PosException.fromBullnym(e),
      );
    } on PosException catch (e) {
      throw PosProvisionException.submission(cause: e);
    }
  }
}
