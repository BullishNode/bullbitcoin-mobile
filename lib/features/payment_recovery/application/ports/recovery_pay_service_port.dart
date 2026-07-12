import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart'
    show BullnymAuthSigner;
import 'package:bb_mobile/features/payment_recovery/application/results/recovery_results.dart';

/// The recovery feature's view of the pay-service. Implementations wrap the
/// shared `bullnym` client, map its `BullnymException` to
/// `PaymentRecoveryException`, and return DOMAIN types only — a bullnym DTO
/// never crosses this boundary.
abstract interface class RecoveryPayServicePort {
  /// Signed `invoice-recovery-list` detection. Always available behind auth;
  /// the result's `recoveryEnabled` reports the server recover flag.
  Future<RecoverableSwapsResult> listRecoverable({
    required BullnymAuthSigner signer,
  });

  /// Signed `invoice-recover` (linked-only). [nym] is signed into the payload
  /// and used to build the per-nym URL. First-write-wins destination;
  /// idempotent retry returns the same txid.
  Future<RecoverResult> recover({
    required BullnymAuthSigner signer,
    required String nym,
    required String invoiceId,
    required String btcAddress,
  });
}
