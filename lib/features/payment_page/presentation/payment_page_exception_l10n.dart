import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page_error.dart';
import 'package:flutter/widgets.dart';

extension PaymentPageExceptionL10n on PaymentPageException {
  String toTranslated(BuildContext context) => switch (kind) {
    PaymentPageErrorKind.invalidInput =>
      context.loc.paymentPageErrorInvalidInput,
    PaymentPageErrorKind.aliasTaken => context.loc.paymentPageAliasTaken,
    PaymentPageErrorKind.aliasAlreadyAssigned =>
      context.loc.paymentPageAliasAlreadyAssigned,
    PaymentPageErrorKind.nymTaken => context.loc.getPaidNymTaken,
    PaymentPageErrorKind.nymReserved => context.loc.getPaidNymReserved,
    PaymentPageErrorKind.nymInvalid => context.loc.getPaidNymInvalid,
    PaymentPageErrorKind.noNym => context.loc.paymentPageErrorNoNym,
    PaymentPageErrorKind.noDefaultBitcoinWallet =>
      context.loc.paymentPageErrorNoDefaultWallet,
    PaymentPageErrorKind.localPreparationFailed =>
      context.loc.paymentPageErrorSetupFailed,
    PaymentPageErrorKind.network ||
    PaymentPageErrorKind.timeout => context.loc.paymentPageErrorConnection,
    PaymentPageErrorKind.notFound => context.loc.paymentPageErrorNotFound,
    PaymentPageErrorKind.rejected => context.loc.paymentPageErrorRejected,
    PaymentPageErrorKind.authError => context.loc.paymentPageErrorAuth,
    PaymentPageErrorKind.server => context.loc.paymentPageErrorServer,
    PaymentPageErrorKind.invalidServerResponse ||
    PaymentPageErrorKind.signingFailed ||
    PaymentPageErrorKind.unexpected => context.loc.paymentPageErrorUnexpected,
  };
}
