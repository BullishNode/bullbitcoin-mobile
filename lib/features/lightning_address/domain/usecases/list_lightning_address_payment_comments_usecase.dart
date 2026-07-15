import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_payment_comment.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lightning_address_error_mapping.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';

/// Protocol composition for Bullnym's signed, identity-wide private comment
/// history. Confidential wallet material stays behind this use-case boundary.
class ListLightningAddressPaymentCommentsUsecase {
  final BullnymFacade _bullnym;
  final NostrIdentityFacade _nostrIdentity;

  const ListLightningAddressPaymentCommentsUsecase(
    this._bullnym,
    this._nostrIdentity,
  );

  Future<LightningAddressPaymentCommentPage> execute({
    required String xprvBase58,
    required int page,
    required int pageSize,
  }) async {
    try {
      final signer = BullnymAuthSigner(
        npubHex: _nostrIdentity.deriveBullnymServerAuthPublicKeyFromXprv(
          xprvBase58,
        ),
        signHashHex: (messageHashHex) =>
            _nostrIdentity.signBullnymServerAuthHashFromXprv(
              xprvBase58: xprvBase58,
              messageHashHex: messageHashHex,
            ),
      );
      final result = await _bullnym.listLnurlCommentHistory(
        signer: signer,
        page: page,
        pageSize: pageSize,
      );
      return switch (result) {
        Ok(:final value) => LightningAddressPaymentCommentPage(
          comments: [
            for (final item in value.comments)
              LightningAddressPaymentComment(
                intentId: item.intentId,
                nym: item.nym,
                amountMsat: item.amountMsat,
                comment: item.comment,
                receivedAt: DateTime.fromMillisecondsSinceEpoch(
                  item.receivedAtUnix * 1000,
                  isUtc: true,
                ),
              ),
          ],
          page: value.page,
          pageSize: value.pageSize,
          hasMore: value.hasMore,
        ),
        Err(:final failure) => throw mapBullnymToLightningAddressException(
          failure,
        ),
      };
    } on LightningAddressException {
      rethrow;
    } catch (_) {
      throw const LightningAddressException.unexpected();
    }
  }
}
