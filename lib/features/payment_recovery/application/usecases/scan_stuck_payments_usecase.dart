import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart'
    show BullnymAuthSigner;
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_identity_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_pay_service_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/results/recovery_results.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/payment_recovery_error.dart';
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:bb_mobile/features/payment_recovery/domain/repositories/payment_recovery_repository.dart';

/// Outcome of a detection scan. [recoveryEnabled] is the server's
/// `chain_swap_merchant_recovery` flag (server-global, kept on cubit state, not
/// persisted per-row). [hasMore] true means the server cap was hit → route to
/// "contact support".
class ScanResult {
  final bool recoveryEnabled;
  final int needsAttentionCount;
  final bool hasMore;

  const ScanResult({
    required this.recoveryEnabled,
    required this.needsAttentionCount,
    required this.hasMore,
  });

  static const empty = ScanResult(
    recoveryEnabled: false,
    needsAttentionCount: 0,
    hasMore: false,
  );
}

/// Detects stuck (recoverable) chain swaps via the SIGNED, npub-scoped
/// `invoice-recovery-list` endpoint (the sole detection signal — never the
/// public status endpoint) and reconciles them into the durable store.
///
/// - Identity: npub signer only (no nym lookup, no active registration). If no
///   default wallet / seed is available (locked, superwallet mode) the scan is
///   a no-op.
/// - Server returns one row per swap; this folds them to one row per invoice
///   (the actionable swap wins) and adopts the server-echoed committed
///   `refund_address`/`refund_txid` on a fresh install, never overwriting a
///   locally-committed address (a mismatch is surfaced as `failed`).
/// - A route-absent server (pre-deploy) maps to `recoveryUnavailable` and is
///   inert: no rows, no error surface.
class ScanStuckPaymentsUsecase {
  final RecoveryIdentityPort _identity;
  final RecoveryPayServicePort _payService;
  final PaymentRecoveryRepository _repository;
  final int Function() _nowSecs;

  ScanStuckPaymentsUsecase({
    required this._identity,
    required this._payService,
    required this._repository,
    required this._nowSecs,
  });

  Future<ScanResult> execute() async {
    final BullnymAuthSigner signer;
    try {
      signer = await _identity.getSigningHandle();
    } on PaymentRecoveryException {
      // No default wallet / seed (locked, superwallet). Nothing to scan.
      return ScanResult.empty;
    }

    final RecoverableSwapsResult result;
    try {
      result = await _payService.listRecoverable(signer: signer);
    } on PaymentRecoveryException catch (e) {
      // Pre-deploy server (route absent → 404 → recoveryUnavailable) is inert:
      // no rows, no badge, no error surface. Any other error leaves the store
      // as-is and propagates.
      if (e.kind == PaymentRecoveryErrorKind.recoveryUnavailable) {
        return ScanResult.empty;
      }
      rethrow;
    }

    // Fold one-row-per-swap into one target per invoice (actionable swap wins).
    final byInvoice = <String, RecoverableSwapRecord>{};
    for (final swap in result.swaps) {
      final existing = byInvoice[swap.invoiceId];
      if (existing == null ||
          _statusPriority(swap.recoveryStatus) <
              _statusPriority(existing.recoveryStatus)) {
        byInvoice[swap.invoiceId] = swap;
      }
    }

    final now = _nowSecs();
    final seenInvoiceIds = <String>{};
    for (final swap in byInvoice.values) {
      seenInvoiceIds.add(swap.invoiceId);
      final existing = await _repository.fetch(swap.invoiceId);
      await _repository.upsert(_reconcile(existing, swap, now));
    }

    // Locally-persisted non-terminal rows the server no longer returns are
    // stale (recovered elsewhere / dropped): mark dismissed. `recovered`/
    // `dismissed` rows are left untouched (history until acknowledged).
    final persisted = await _repository.fetchAll();
    for (final row in persisted) {
      if (seenInvoiceIds.contains(row.invoiceId)) continue;
      if (row.state == RecoveryState.recovered ||
          row.state == RecoveryState.dismissed) {
        continue;
      }
      await _repository.upsert(row.copyWith(state: RecoveryState.dismissed));
    }

    final needsAttention =
        (await _repository.fetchAll()).where((p) => p.needsAttention).length;
    return ScanResult(
      recoveryEnabled: result.recoveryEnabled,
      needsAttentionCount: needsAttention,
      hasMore: result.hasMore,
    );
  }

  /// Merge a server swap record with any existing local row, adopting the
  /// server-committed reconciliation echo and preserving local bookkeeping.
  StuckPayment _reconcile(
    StuckPayment? existing,
    RecoverableSwapRecord swap,
    int now,
  ) {
    // Detect a committed-address mismatch (multi-device race / corruption):
    // never overwrite the local address — surface it as failed.
    final localAddress = existing?.refundAddress;
    final echoedAddress = swap.refundAddress;
    final mismatch = localAddress != null &&
        echoedAddress != null &&
        localAddress != echoedAddress;

    // First-write-wins: keep the locally committed address; otherwise adopt the
    // server echo (fresh install / another device committed first).
    final committedAddress = localAddress ?? echoedAddress;

    final RecoveryState state;
    String? errorCode = existing?.lastErrorCode;
    if (mismatch) {
      state = RecoveryState.failed;
      errorCode = 'RecoveryAddressMismatch';
    } else {
      state = _mapState(swap.recoveryStatus, committedAddress);
      // A fresh successful mapping clears a prior transient error.
      if (state != RecoveryState.failed) errorCode = null;
    }

    return StuckPayment(
      invoiceId: swap.invoiceId,
      nym: swap.nym,
      state: state,
      refundAddress: mismatch ? localAddress : committedAddress,
      refundTxid: swap.refundTxid ?? existing?.refundTxid,
      lockupAddress: swap.lockupAddress,
      amountSat: swap.userLockAmountSat,
      fiatCurrency: swap.fiatCurrency,
      fiatAmountMinor: swap.fiatAmountMinor,
      detectedAtUnix: existing?.detectedAtUnix ?? now,
      lastAttemptAtUnix: existing?.lastAttemptAtUnix,
      attemptCount: existing?.attemptCount ?? 0,
      lastErrorCode: errorCode,
      acknowledged: existing?.acknowledged ?? false,
    );
  }

  RecoveryState _mapState(String serverStatus, String? committedAddress) {
    switch (serverStatus) {
      case ServerRecoveryStatus.refunded:
        return RecoveryState.recovered;
      case ServerRecoveryStatus.refunding:
        return RecoveryState.recovering;
      case ServerRecoveryStatus.refundDue:
        return committedAddress != null
            ? RecoveryState.addressCommitted
            : RecoveryState.detected;
      default:
        return RecoveryState.inFlightUnknown;
    }
  }

  int _statusPriority(String serverStatus) {
    switch (serverStatus) {
      case ServerRecoveryStatus.refundDue:
        return 0;
      case ServerRecoveryStatus.refunding:
        return 1;
      case ServerRecoveryStatus.refunded:
        return 2;
      default:
        return 3;
    }
  }
}
