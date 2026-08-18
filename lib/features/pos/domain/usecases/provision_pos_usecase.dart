import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/pos/domain/pos_error.dart';
import 'package:bb_mobile/features/pos/domain/pos_terminal.dart';
import 'package:bb_mobile/features/pos/domain/pos_validation.dart';
import 'package:bb_mobile/features/pos/domain/usecases/prepare_pos_wallet_usecase.dart';
import 'package:bb_mobile/features/pos/domain/usecases/resolve_pos_identity_usecase.dart';

/// Validates, prepares wallet 103, and submits the server-authoritative POS
/// row. The server-returned public URL is already validated by Bullnym; no
/// client-side terminal URL base is accepted here.
class ProvisionPosUsecase {
  final ResolvePosIdentityUsecase _resolveIdentity;
  final PreparePosWalletUsecase _prepareWallet;
  final BullnymFacade _bullnym;

  const ProvisionPosUsecase({
    required this._resolveIdentity,
    required this._prepareWallet,
    required this._bullnym,
  });

  Future<PosTerminal> execute({
    required String label,
    required String displayCurrency,
    String? aliasClaim,
  }) async {
    PosProvisionCommand(
      label: label,
      displayCurrency: displayCurrency,
      aliasClaim: aliasClaim,
    ).validate();
    final normalizedAliasClaim = aliasClaim == null
        ? null
        : normalizePosAlias(aliasClaim);

    final ResolvedPosIdentity identity;
    final String ctDescriptor;
    try {
      identity = await _resolveIdentity.execute();
      final preparedWallet = await _prepareWallet.execute();
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
      final result = await _bullnym.saveDonationPage(
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
        aliasIntent: normalizedAliasClaim == null
            ? const BullnymAliasIntent.preserve()
            : BullnymAliasIntent.claim(
                BullnymPublicName.aliasClaim(normalizedAliasClaim),
              ),
      );
      switch (result) {
        case Ok(:final value):
          final terminal = PosTerminal.fromBullnym(value);
          if (terminal.nym != identity.nym ||
              (normalizedAliasClaim != null &&
                  terminal.alias != normalizedAliasClaim)) {
            throw const PosException.invalidServerResponse();
          }
          return terminal;
        case Err(:final failure):
          throw PosException.fromBullnym(failure);
      }
    } on PosException catch (e) {
      throw PosProvisionException.submission(cause: e);
    }
  }
}
