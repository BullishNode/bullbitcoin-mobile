import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_pay_service_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/results/recovery_results.dart';
import 'package:bb_mobile/features/payment_recovery/domain/payment_recovery_error.dart';

/// Implements [RecoveryPayServicePort] over the shared `bullnym` client. Maps
/// wire DTOs → domain results and every `BullnymException` →
/// `PaymentRecoveryException`, so no wire type or raw server reason escapes.
class RecoveryPayServiceDatasource implements RecoveryPayServicePort {
  final BullnymFacade _bullnym;

  const RecoveryPayServiceDatasource({required this._bullnym});

  @override
  Future<RecoverableSwapsResult> listRecoverable({
    required BullnymAuthSigner signer,
  }) async {
    try {
      final list = await _bullnym.listRecoverableChainSwaps(signer: signer);
      return RecoverableSwapsResult(
        recoveryEnabled: list.recoveryEnabled,
        hasMore: list.hasMore,
        swaps: list.items
            .map(
              (i) => RecoverableSwapRecord(
                invoiceId: i.invoiceId,
                nym: i.nym,
                recoveryStatus: i.recoveryStatus,
                userLockAmountSat: i.userLockAmountSat,
                serverLockAmountSat: i.serverLockAmountSat,
                lockupAddress: i.lockupAddress,
                refundAddress: i.refundAddress,
                refundTxid: i.refundTxid,
                swapCreatedAtUnix: i.swapCreatedAtUnix,
                swapUpdatedAtUnix: i.swapUpdatedAtUnix,
                invoiceStatus: i.invoiceStatus,
                invoiceAmountSat: i.invoiceAmountSat,
                fiatAmountMinor: i.fiatAmountMinor,
                fiatCurrency: i.fiatCurrency,
                publicDescription: i.publicDescription,
                invoiceNumber: i.invoiceNumber,
                invoiceCreatedAtUnix: i.invoiceCreatedAtUnix,
              ),
            )
            .toList(),
      );
    } on BullnymException catch (e) {
      throw PaymentRecoveryException.fromBullnym(e);
    }
  }

  @override
  Future<RecoverResult> recover({
    required BullnymAuthSigner signer,
    required String nym,
    required String invoiceId,
    required String btcAddress,
  }) async {
    try {
      final r = await _bullnym.recoverChainSwap(
        signer: signer,
        nym: nym,
        invoiceId: invoiceId,
        btcAddress: btcAddress,
      );
      return RecoverResult(status: r.status, txid: r.txid);
    } on BullnymException catch (e) {
      throw PaymentRecoveryException.fromBullnym(e);
    }
  }
}
