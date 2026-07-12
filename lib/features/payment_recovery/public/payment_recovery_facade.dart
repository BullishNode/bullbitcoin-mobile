import 'package:bb_mobile/features/payment_recovery/application/usecases/dismiss_stuck_payment_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/recover_stuck_payment_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/scan_stuck_payments_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/watch_stuck_payments_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';

/// Public API of the payment-recovery feature for other features (the Get Paid
/// dashboard consumes it for the stuck-payment badge and scan-on-open).
class PaymentRecoveryFacade {
  final ScanStuckPaymentsUsecase _scan;
  final WatchStuckPaymentsUsecase _watch;
  final DismissStuckPaymentUsecase _dismiss;
  final RecoverStuckPaymentUsecase _recover;

  PaymentRecoveryFacade({
    required this._scan,
    required this._watch,
    required this._dismiss,
    required this._recover,
  });

  /// Run one detection scan (single signed GET); reconciles the store. Safe to
  /// call fire-and-forget from the hub/resume hooks.
  Future<ScanResult> scan() => _scan.execute();

  /// Reactive view for badges/lists — emits on every store write.
  Stream<List<StuckPayment>> watch() => _watch.execute();

  /// One-tap recover a stuck payment to the merchant's default Bitcoin wallet.
  /// Commit-before-send + idempotent; the store view ([watch]) reflects the
  /// resulting state (recovering → recovered, or a mapped error state).
  Future<void> recover(String invoiceId) => _recover.execute(invoiceId);

  /// Acknowledge the out-of-band "settle at the till" notice.
  Future<void> acknowledge(String invoiceId) => _dismiss.acknowledge(invoiceId);

  /// Drop a stale/gone detection from the attention list.
  Future<void> dismiss(String invoiceId) => _dismiss.dismiss(invoiceId);

  @override
  String toString() => 'PaymentRecoveryFacade';
}
