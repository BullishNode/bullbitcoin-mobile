import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';

/// A POS/Payment-Page payment whose Bitcoin chain swap is stuck and whose BTC
/// is recoverable by the merchant. One per invoice (§7): the currently
/// actionable swap of an invoice, with per-swap detail folded to display fields.
class StuckPayment {
  final String invoiceId;

  /// Owning nym — used to build the per-nym recover URL.
  final String nym;

  final RecoveryState state;

  /// The committed first-write-wins refund destination (own-wallet address), or
  /// null before one is committed.
  final String? refundAddress;

  /// The broadcast recovery txid, once recovered.
  final String? refundTxid;

  /// The actionable swap's lockup address (swap identity), display/keying only.
  final String? lockupAddress;

  /// Display amount (the payer's BTC lockup, `user_lock_amount_sat`).
  final int? amountSat;
  final String? fiatCurrency;
  final int? fiatAmountMinor;

  final int detectedAtUnix;
  final int? lastAttemptAtUnix;
  final int attemptCount;
  final String? lastErrorCode;

  /// Whether the merchant acknowledged the out-of-band "settle at the till"
  /// notice for a recovered payment.
  final bool acknowledged;

  const StuckPayment({
    required this.invoiceId,
    required this.nym,
    required this.state,
    this.refundAddress,
    this.refundTxid,
    this.lockupAddress,
    this.amountSat,
    this.fiatCurrency,
    this.fiatAmountMinor,
    required this.detectedAtUnix,
    this.lastAttemptAtUnix,
    this.attemptCount = 0,
    this.lastErrorCode,
    this.acknowledged = false,
  });

  bool get isActionable => state.isActionable;
  bool get needsAttention => state.needsAttention;

  StuckPayment copyWith({
    RecoveryState? state,
    String? refundAddress,
    String? refundTxid,
    String? lockupAddress,
    int? amountSat,
    String? fiatCurrency,
    int? fiatAmountMinor,
    int? lastAttemptAtUnix,
    int? attemptCount,
    String? lastErrorCode,
    bool? acknowledged,
  }) {
    return StuckPayment(
      invoiceId: invoiceId,
      nym: nym,
      state: state ?? this.state,
      refundAddress: refundAddress ?? this.refundAddress,
      refundTxid: refundTxid ?? this.refundTxid,
      lockupAddress: lockupAddress ?? this.lockupAddress,
      amountSat: amountSat ?? this.amountSat,
      fiatCurrency: fiatCurrency ?? this.fiatCurrency,
      fiatAmountMinor: fiatAmountMinor ?? this.fiatAmountMinor,
      detectedAtUnix: detectedAtUnix,
      lastAttemptAtUnix: lastAttemptAtUnix ?? this.lastAttemptAtUnix,
      attemptCount: attemptCount ?? this.attemptCount,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }
}
