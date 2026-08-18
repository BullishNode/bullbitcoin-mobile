import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/pos/domain/pos_error.dart';
import 'package:flutter/widgets.dart';

extension PosExceptionL10n on PosException {
  String toTranslated(BuildContext context) => switch (kind) {
    PosErrorKind.invalidInput => context.loc.posErrorInvalidInput,
    PosErrorKind.aliasTaken => context.loc.posAliasTaken,
    PosErrorKind.aliasAlreadyAssigned => context.loc.posAliasAlreadyAssigned,
    PosErrorKind.nymTaken => context.loc.getPaidNymTaken,
    PosErrorKind.nymReserved => context.loc.getPaidNymReserved,
    PosErrorKind.nymInvalid => context.loc.getPaidNymInvalid,
    PosErrorKind.noNym => context.loc.posErrorNoNym,
    PosErrorKind.noDefaultBitcoinWallet => context.loc.posErrorNoDefaultWallet,
    PosErrorKind.localPreparationFailed => context.loc.posErrorSetupFailed,
    PosErrorKind.network ||
    PosErrorKind.timeout => context.loc.posErrorConnection,
    PosErrorKind.notFound => context.loc.posErrorNotFound,
    PosErrorKind.rejected => context.loc.posErrorRejected,
    PosErrorKind.authError => context.loc.posErrorAuth,
    PosErrorKind.server => context.loc.posErrorServer,
    PosErrorKind.invalidServerResponse ||
    PosErrorKind.signingFailed ||
    PosErrorKind.unexpected => context.loc.posErrorUnexpected,
  };
}
