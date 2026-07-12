import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_identity_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_pay_service_port.dart';
import 'package:bb_mobile/features/payment_recovery/domain/payment_recovery_error.dart';
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:bb_mobile/features/payment_recovery/domain/repositories/payment_recovery_repository.dart';

/// One-tap merchant recovery of a stuck chain swap's stranded BTC to the
/// merchant's DEFAULT Bitcoin wallet. Foreground, manual, single-tap only.
///
/// The load-bearing invariant is **commit-before-send**: the refund address is
/// derived once and PERSISTED before any network call, so every retry (client
/// timeout, RecoveryInProgress, app restart) reuses the exact committed bytes —
/// mirroring the server's first-write-wins destination. The address is never
/// re-derived once committed, and a mismatch with a server echo is surfaced by
/// the scan (never overwritten here).
class RecoverStuckPaymentUsecase {
  final RecoveryIdentityPort _identity;
  final RecoveryPayServicePort _payService;
  final PaymentRecoveryRepository _repository;
  final WalletRepository _walletRepository;
  final WalletAddressRepository _walletAddressRepository;
  final GetSettingsUsecase _getSettings;
  final int Function() _nowSecs;

  /// In-memory single-flight guard against a double-tap / concurrent-cubit race
  /// within one process (the persisted `recovering` state guards across opens).
  final Set<String> _inFlight = {};

  RecoverStuckPaymentUsecase({
    required this._identity,
    required this._payService,
    required this._repository,
    required this._walletRepository,
    required this._walletAddressRepository,
    required this._getSettings,
    required this._nowSecs,
  });

  Future<void> execute(String invoiceId) async {
    if (_inFlight.contains(invoiceId)) return;
    _inFlight.add(invoiceId);
    try {
      var row = await _repository.fetch(invoiceId);
      if (row == null) return;
      // Only actionable rows proceed; `recovering` is a no-op (single-flight),
      // and terminal/unknown rows are never recovered.
      if (!row.state.isActionable) return;

      // 1) Resolve the destination — commit BEFORE any network call.
      final String btcAddress;
      if (row.refundAddress != null) {
        btcAddress = row.refundAddress!; // reuse verbatim (first-write-wins)
      } else {
        btcAddress = await _freshDefaultWalletAddress();
        row = row.copyWith(
          refundAddress: btcAddress,
          state: RecoveryState.addressCommitted,
        );
        await _repository.upsert(row); // committed & durable before the POST
      }

      // 2) Resolve signer, mark recovering, POST.
      final signer = await _identity.getSigningHandle();
      row = row.copyWith(
        state: RecoveryState.recovering,
        lastAttemptAtUnix: _nowSecs(),
        attemptCount: row.attemptCount + 1,
      );
      await _repository.upsert(row);

      final result = await _payService.recover(
        signer: signer,
        nym: row.nym,
        invoiceId: invoiceId,
        btcAddress: btcAddress,
      );

      // 3) Success (idempotent retry returns the same txid).
      await _repository.upsert(
        row.copyWith(
          state: RecoveryState.recovered,
          refundTxid: result.txid,
        ),
      );
    } on PaymentRecoveryException catch (e) {
      await _handleError(invoiceId, e);
    } finally {
      _inFlight.remove(invoiceId);
    }
  }

  Future<void> _handleError(String invoiceId, PaymentRecoveryException e) async {
    final row = await _repository.fetch(invoiceId);
    if (row == null) return;
    final hasAddress = row.refundAddress != null;
    // Retryable-but-actionable: keep the committed address so the next tap
    // reuses it. Terminal-ish: surface as failed for the merchant to inspect.
    final RecoveryState next;
    switch (e.kind) {
      case PaymentRecoveryErrorKind.recoveryInProgress:
        // Broadcast is in flight server-side — stay `recovering`; the cubit
        // polls the recoverable endpoint to completion.
        next = RecoveryState.recovering;
      case PaymentRecoveryErrorKind.network:
      case PaymentRecoveryErrorKind.timeout:
      case PaymentRecoveryErrorKind.server:
      case PaymentRecoveryErrorKind.recoveryUnavailable:
        // Retryable: an address is already committed, so a later tap resends
        // the same bytes (idempotent server).
        next = hasAddress
            ? RecoveryState.addressCommitted
            : RecoveryState.detected;
      case PaymentRecoveryErrorKind.noDefaultBitcoinWallet:
      case PaymentRecoveryErrorKind.signingFailed:
        // Can't act right now (locked / superwallet); keep it visible.
        next = hasAddress
            ? RecoveryState.addressCommitted
            : RecoveryState.detected;
      case PaymentRecoveryErrorKind.addressMismatch:
      case PaymentRecoveryErrorKind.addressInvalid:
      case PaymentRecoveryErrorKind.notFound:
      case PaymentRecoveryErrorKind.recoveryNotAvailable:
      case PaymentRecoveryErrorKind.invalidServerResponse:
      case PaymentRecoveryErrorKind.unexpected:
        // Surface; a subsequent scan reconciles (echo may flip to recovered /
        // dismissed, or confirm a genuine mismatch).
        next = RecoveryState.failed;
    }
    await _repository.upsert(
      row.copyWith(state: next, lastErrorCode: e.code),
    );
  }

  Future<String> _freshDefaultWalletAddress() async {
    final settings = await _getSettings.execute();
    final wallets = await _walletRepository.getWallets(
      environment: settings.environment,
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) {
      throw const PaymentRecoveryException.noDefaultBitcoinWallet();
    }
    final address = await _walletAddressRepository.generateNewReceiveAddress(
      walletId: wallets.first.id,
    );
    return address.address;
  }
}
