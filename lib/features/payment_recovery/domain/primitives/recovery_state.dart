/// Local recovery lifecycle for a stuck payment (per invoice). Distinct from
/// the server chain-swap status (`refund_due`/`refunding`/`refunded`): this
/// folds the server status together with local progress (address committed,
/// broadcast in flight, acknowledged) so the UI has a single state to render.
///
/// Mapping from the server `recovery_status` at scan time (§5.2.4):
///   refunded (+txid)                 -> recovered
///   refunding                        -> recovering
///   refund_due + committed address   -> addressCommitted
///   refund_due + no address          -> detected
///   unknown/newer status             -> inFlightUnknown (visible, no action)
enum RecoveryState {
  /// `refund_due`, no destination committed yet — recoverable now.
  detected,

  /// `refund_due` with a committed refund address (locally or server-echoed) —
  /// a retry must reuse that exact address (first-write-wins).
  addressCommitted,

  /// `refunding` — broadcast in flight; poll to completion.
  recovering,

  /// `refunded` — terminal success; `refundTxid` present.
  recovered,

  /// A recover attempt failed in a non-terminal way (see `lastErrorCode`).
  failed,

  /// No longer recoverable / gone from the server (stale detection).
  dismissed,

  /// The server reported a recovery status this client version does not know.
  /// Shown read-only with the action disabled — a newer server state must
  /// never hide a stuck payment, nor enable a recover button on a guess.
  inFlightUnknown;

  String get dbValue => name;

  static RecoveryState fromDbValue(String value) {
    return RecoveryState.values.firstWhere(
      (s) => s.name == value,
      orElse: () => RecoveryState.inFlightUnknown,
    );
  }

  /// True when the merchant may trigger a recover POST (subject to the
  /// server's `recoveryEnabled` flag, enforced separately).
  bool get isActionable =>
      this == RecoveryState.detected ||
      this == RecoveryState.addressCommitted ||
      this == RecoveryState.failed;

  /// True when recovery is still outstanding (contributes to the hub badge).
  bool get needsAttention =>
      this == RecoveryState.detected ||
      this == RecoveryState.addressCommitted ||
      this == RecoveryState.recovering ||
      this == RecoveryState.failed ||
      this == RecoveryState.inFlightUnknown;
}

/// Server chain-swap `recovery_status` wire strings (bullnym `chain_swap_records`).
abstract final class ServerRecoveryStatus {
  static const String refundDue = 'refund_due';
  static const String refunding = 'refunding';
  static const String refunded = 'refunded';
}
