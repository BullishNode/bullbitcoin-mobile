// Domain-shaped results for the recovery pay-service port. A bullnym wire DTO
// never crosses the port boundary (mirrors the invoices charter): the
// datasource maps DTOs to these and translates every `BullnymException` to a
// `PaymentRecoveryException`.

/// One recoverable chain swap (domain mirror of the server `RecoverableItem`).
/// ONE PER SWAP — an invoice with two stuck swaps yields two records,
/// distinguished by [lockupAddress].
class RecoverableSwapRecord {
  final String invoiceId;
  final String nym;
  final String recoveryStatus; // 'refund_due' | 'refunding' | 'refunded'
  final int userLockAmountSat;
  final int serverLockAmountSat;
  final String lockupAddress;
  final String? refundAddress;
  final String? refundTxid;
  final int swapCreatedAtUnix;
  final int swapUpdatedAtUnix;
  final String invoiceStatus;
  final int invoiceAmountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final String? publicDescription;
  final String? invoiceNumber;
  final int invoiceCreatedAtUnix;

  const RecoverableSwapRecord({
    required this.invoiceId,
    required this.nym,
    required this.recoveryStatus,
    required this.userLockAmountSat,
    required this.serverLockAmountSat,
    required this.lockupAddress,
    this.refundAddress,
    this.refundTxid,
    required this.swapCreatedAtUnix,
    required this.swapUpdatedAtUnix,
    required this.invoiceStatus,
    required this.invoiceAmountSat,
    this.fiatAmountMinor,
    this.fiatCurrency,
    this.publicDescription,
    this.invoiceNumber,
    required this.invoiceCreatedAtUnix,
  });
}

/// The detection result: the npub's recoverable swaps plus the server flags.
class RecoverableSwapsResult {
  /// Server `chain_swap_merchant_recovery` flag — drives "Recover now" vs
  /// "Contact support" UI; detection itself is always-on.
  final bool recoveryEnabled;

  /// True iff the server cap was hit (operator incident) → "contact support".
  final bool hasMore;

  final List<RecoverableSwapRecord> swaps;

  const RecoverableSwapsResult({
    required this.recoveryEnabled,
    required this.hasMore,
    required this.swaps,
  });

  int get count => swaps.length;
}

/// The recover-action result (`{status, txid}`).
class RecoverResult {
  final String status;
  final String txid;

  const RecoverResult({required this.status, required this.txid});
}
