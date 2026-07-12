import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:bb_mobile/features/payment_recovery/domain/repositories/payment_recovery_repository.dart';

/// Marks a stuck payment acknowledged (the merchant saw the out-of-band
/// "settle at the till" notice) or dismisses a recovered/gone row from the
/// attention list. Recovery bookkeeping (address/txid) is retained.
class DismissStuckPaymentUsecase {
  final PaymentRecoveryRepository _repository;

  DismissStuckPaymentUsecase({required this._repository});

  /// Acknowledge the out-of-band notice for a recovered payment.
  Future<void> acknowledge(String invoiceId) async {
    final row = await _repository.fetch(invoiceId);
    if (row == null) return;
    await _repository.upsert(row.copyWith(acknowledged: true));
  }

  /// Drop a row from the attention list (e.g. a stale detection the merchant
  /// dismisses). Retains no further tracking.
  Future<void> dismiss(String invoiceId) async {
    final row = await _repository.fetch(invoiceId);
    if (row == null) return;
    await _repository.upsert(row.copyWith(state: RecoveryState.dismissed));
  }
}
