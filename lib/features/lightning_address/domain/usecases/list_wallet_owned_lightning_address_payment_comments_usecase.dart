import 'package:bb_mobile/features/lightning_address/domain/lightning_address_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_payment_comment.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/list_lightning_address_payment_comments_usecase.dart';

class ListWalletOwnedLightningAddressPaymentCommentsUsecase {
  final LightningAddressDefaultWalletXprvPort _defaultWalletXprv;
  final ListLightningAddressPaymentCommentsUsecase _listComments;

  const ListWalletOwnedLightningAddressPaymentCommentsUsecase(
    this._defaultWalletXprv,
    this._listComments,
  );

  Future<LightningAddressPaymentCommentPage> execute({
    required int page,
    required int pageSize,
  }) async {
    final xprvBase58 = await _deriveDefaultWalletXprv();
    return _listComments.execute(
      xprvBase58: xprvBase58,
      page: page,
      pageSize: pageSize,
    );
  }

  Future<String> _deriveDefaultWalletXprv() async {
    try {
      return await _defaultWalletXprv.deriveDefaultWalletXprv();
    } on LightningAddressException {
      rethrow;
    } catch (error) {
      throw LightningAddressException.localPreparationFailed(
        code: error.runtimeType.toString(),
        retryable: true,
      );
    }
  }
}
