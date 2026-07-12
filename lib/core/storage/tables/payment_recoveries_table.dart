import 'package:drift/drift.dart';

/// Durable per-INVOICE recovery bookkeeping for stuck POS/Payment-Page chain
/// swaps (PR29). The bullnym detection endpoint returns one row per chain swap,
/// but the recover ACTION is per-invoice (one committed refund address reused
/// across an invoice's swaps), so this table is keyed by `invoiceId`; per-swap
/// detail (`lockupAddress`, amounts) is display-only.
///
/// This table is what makes first-write-wins address reuse and idempotent
/// retry survive an app restart. It does NOT survive a wipe/reinstall — after a
/// restore the source of truth is the server echo on the recoverable endpoint
/// (committed `refund_address`/`refund_txid`), which the scan re-adopts.
///
/// `recoveryEnabled` is deliberately NOT stored here: it is a server-global
/// flag from the last scan, kept on cubit state rather than per-row.
@DataClassName('PaymentRecoveryRow')
class PaymentRecoveries extends Table {
  /// Server invoice id — the primary key.
  TextColumn get invoiceId => text()();

  /// Owning nym captured at detection time; used to build the per-nym recover
  /// URL (`POST /api/v1/<nym>/invoices/<invoiceId>/recover`).
  TextColumn get nym => text()();

  /// The `recovery_state` wire string (see `RecoveryState`).
  TextColumn get state => text()();

  /// The COMMITTED first-write-wins refund destination. Once set it is never
  /// rewritten (a mismatch with a later server echo is surfaced, not fixed).
  TextColumn get refundAddress => text().nullable()();

  /// The broadcast recovery txid, once `refunded`.
  TextColumn get refundTxid => text().nullable()();

  /// Most-recently-actionable swap's lockup address — swap identity for
  /// display/keying; the local row is still per-invoice.
  TextColumn get lockupAddress => text().nullable()();

  /// Display-only amount from the recoverable row (`user_lock_amount_sat`).
  IntColumn get amountSat => integer().nullable()();
  TextColumn get fiatCurrency => text().nullable()();
  IntColumn get fiatAmountMinor => integer().nullable()();

  IntColumn get detectedAtUnix => integer()();
  IntColumn get lastAttemptAtUnix => integer().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastErrorCode => text().nullable()();

  /// Whether the merchant acknowledged the out-of-band "settle at the till"
  /// notice for a recovered payment.
  BoolColumn get acknowledged => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {invoiceId};
}
