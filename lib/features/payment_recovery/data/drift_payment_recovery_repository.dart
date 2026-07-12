import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/payment_recovery_error.dart';
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:bb_mobile/features/payment_recovery/domain/repositories/payment_recovery_repository.dart';
import 'package:drift/drift.dart';

/// Drift-backed [PaymentRecoveryRepository]. One row per invoice, keyed by
/// `invoiceId`. Callers read-modify-write the full row (via [upsert]) so the
/// committed refund address is never clobbered by a partial update.
class DriftPaymentRecoveryRepository implements PaymentRecoveryRepository {
  final SqliteDatabase _database;

  DriftPaymentRecoveryRepository({required this._database});

  @override
  Future<List<StuckPayment>> fetchAll() async {
    try {
      final rows =
          await (_database.select(_database.paymentRecoveries)
                ..orderBy([(t) => OrderingTerm.desc(t.detectedAtUnix)]))
              .get();
      return rows.map(_toEntity).toList();
    } catch (e) {
      throw PaymentRecoveryException.storage(cause: e);
    }
  }

  @override
  Future<StuckPayment?> fetch(String invoiceId) async {
    try {
      final row =
          await (_database.select(_database.paymentRecoveries)
                ..where((t) => t.invoiceId.equals(invoiceId)))
              .getSingleOrNull();
      return row == null ? null : _toEntity(row);
    } catch (e) {
      throw PaymentRecoveryException.storage(cause: e);
    }
  }

  @override
  Stream<List<StuckPayment>> watch() {
    return (_database.select(_database.paymentRecoveries)
          ..orderBy([(t) => OrderingTerm.desc(t.detectedAtUnix)]))
        .watch()
        .map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<void> upsert(StuckPayment p) async {
    try {
      await _database
          .into(_database.paymentRecoveries)
          .insertOnConflictUpdate(
            PaymentRecoveriesCompanion(
              invoiceId: Value(p.invoiceId),
              nym: Value(p.nym),
              state: Value(p.state.dbValue),
              refundAddress: Value(p.refundAddress),
              refundTxid: Value(p.refundTxid),
              lockupAddress: Value(p.lockupAddress),
              amountSat: Value(p.amountSat),
              fiatCurrency: Value(p.fiatCurrency),
              fiatAmountMinor: Value(p.fiatAmountMinor),
              detectedAtUnix: Value(p.detectedAtUnix),
              lastAttemptAtUnix: Value(p.lastAttemptAtUnix),
              attemptCount: Value(p.attemptCount),
              lastErrorCode: Value(p.lastErrorCode),
              acknowledged: Value(p.acknowledged),
            ),
          );
    } catch (e) {
      throw PaymentRecoveryException.storage(cause: e);
    }
  }

  @override
  Future<void> delete(String invoiceId) async {
    try {
      await (_database.delete(_database.paymentRecoveries)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .go();
    } catch (e) {
      throw PaymentRecoveryException.storage(cause: e);
    }
  }

  StuckPayment _toEntity(PaymentRecoveryRow row) {
    return StuckPayment(
      invoiceId: row.invoiceId,
      nym: row.nym,
      state: RecoveryState.fromDbValue(row.state),
      refundAddress: row.refundAddress,
      refundTxid: row.refundTxid,
      lockupAddress: row.lockupAddress,
      amountSat: row.amountSat,
      fiatCurrency: row.fiatCurrency,
      fiatAmountMinor: row.fiatAmountMinor,
      detectedAtUnix: row.detectedAtUnix,
      lastAttemptAtUnix: row.lastAttemptAtUnix,
      attemptCount: row.attemptCount,
      lastErrorCode: row.lastErrorCode,
      acknowledged: row.acknowledged,
    );
  }
}
