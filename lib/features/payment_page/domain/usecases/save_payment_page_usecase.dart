import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page_error.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page_validation.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/prepare_payment_page_wallet_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/resolve_payment_page_identity_usecase.dart';

/// Validates, prepares wallet 102, and submits the server-authoritative
/// Payment Page row. Alias claims are explicit; omitted aliases preserve the
/// existing server value. Wallet preparation remains the only source of the
/// confidential descriptor and records the manifest independently.
class SavePaymentPageUsecase {
  final ResolvePaymentPageIdentityUsecase _resolveIdentity;
  final PreparePaymentPageWalletUsecase _prepareWallet;
  final BullnymFacade _bullnym;

  const SavePaymentPageUsecase({
    required this._resolveIdentity,
    required this._prepareWallet,
    required this._bullnym,
  });

  Future<PaymentPage> execute({
    required String header,
    required String description,
    required String displayCurrency,
    String website = '',
    String twitter = '',
    String instagram = '',
    String? aliasClaim,
  }) async {
    SavePaymentPageCommand(
      header: header,
      description: description,
      displayCurrency: displayCurrency,
      website: website,
      twitter: twitter,
      instagram: instagram,
      aliasClaim: aliasClaim,
    ).validate();
    final normalizedAliasClaim = aliasClaim == null
        ? null
        : normalizePaymentPageAlias(aliasClaim);

    final ResolvedPaymentPageIdentity identity;
    final String ctDescriptor;
    try {
      identity = await _resolveIdentity.execute();
      final preparedWallet = await _prepareWallet.execute();
      ctDescriptor = preparedWallet.ctDescriptor;
      if (ctDescriptor.isEmpty) {
        throw const PaymentPageException.localPreparationFailed(
          code: 'EmptyPageDescriptor',
          retryable: false,
        );
      }
    } on PaymentPageException catch (e) {
      throw PaymentPageSaveException.localPreparation(cause: e);
    }

    try {
      final result = await _bullnym.saveDonationPage(
        signer: identity.signer,
        nym: identity.nym,
        ctDescriptor: ctDescriptor,
        header: header,
        description: description,
        displayCurrency: displayCurrency,
        website: website,
        twitter: twitter,
        instagram: instagram,
        enabled: true,
        kind: bullnymDonationPageKindPaymentPage,
        aliasIntent: normalizedAliasClaim == null
            ? const BullnymAliasIntent.preserve()
            : BullnymAliasIntent.claim(
                BullnymPublicName.aliasClaim(normalizedAliasClaim),
              ),
      );
      switch (result) {
        case Ok(:final value):
          final page = PaymentPage.fromBullnym(value);
          if (page.nym != identity.nym ||
              (normalizedAliasClaim != null &&
                  page.alias != normalizedAliasClaim)) {
            throw const PaymentPageException.invalidServerResponse();
          }
          return page;
        case Err(:final failure):
          throw PaymentPageException.fromBullnym(failure);
      }
    } on PaymentPageException catch (e) {
      throw PaymentPageSaveException.submission(cause: e);
    }
  }
}
