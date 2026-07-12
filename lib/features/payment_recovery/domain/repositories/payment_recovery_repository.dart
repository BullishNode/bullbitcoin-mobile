import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';

/// Durable local store of stuck-payment recovery bookkeeping (one row per
/// invoice). Backed by Drift. All methods throw
/// `PaymentRecoveryException.storage` on a storage failure.
abstract interface class PaymentRecoveryRepository {
  /// All persisted rows (any state), newest-detected first.
  Future<List<StuckPayment>> fetchAll();

  /// A single invoice's row, or null.
  Future<StuckPayment?> fetch(String invoiceId);

  /// Reactive view for badges/lists — emits on every write.
  Stream<List<StuckPayment>> watch();

  /// Insert or update a row (read-modify-write at the call site as needed).
  Future<void> upsert(StuckPayment payment);

  /// Delete a row (used when a detection is confirmed gone).
  Future<void> delete(String invoiceId);
}
