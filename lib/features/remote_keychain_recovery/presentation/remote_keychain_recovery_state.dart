import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';

enum RemoteKeychainRecoveryStatus {
  idle,
  requiresRelayDisclosure,
  checking,
  olderManifestAvailable,
  restoring,
  restored,
  partiallyRestored,
  nothingToRestore,
  restoreFailed,
  skipped,
  noManifestFound,
  relaysUnavailable,
  noRecoverableManifest,
  unsupportedNewerManifest,
  defaultWalletUnavailable,
  failed,
}

class RemoteKeychainRecoveryState {
  final RemoteKeychainRecoveryStatus status;
  final int restoredCount;
  final int failedCount;
  final bool hasProductReactivationRequired;
  final int? newestEventCreatedAt;
  final int? selectedEventCreatedAt;

  /// True when the restored manifest was an older backup selected after the
  /// newest one could not be used - PR23's "restored from an older backup"
  /// confirmation reads this together with the timestamps (P22d, decision [D]).
  final bool isOlderRestore;

  /// The typed failure for a failed terminal state. Only the typed kind and its
  /// `toTranslated` message reach presentation; the raw cause stays in logs
  /// (P22b).
  final RemoteKeychainRecoveryException? failure;

  /// The DG-3 auto-heal interpretation the UI renders for recovered
  /// bullnym-backed products. Uses the Lightning Address feature's exported
  /// contract type (charter A3). Null when nothing was healed;
  /// [hasProductReactivationRequired] stays the raw restore signal.
  final LightningAddressHealOutcome? healOutcome;

  /// The DG-3 auto-heal interpretation for the recovered Donation Page (102).
  /// Null when the page was not flagged for reactivation.
  final PaymentPageHealOutcome? paymentPageHealOutcome;

  /// The DG-3 auto-heal interpretation for the recovered Point of Sale (103).
  /// Null when the POS was not flagged for reactivation.
  final PosHealOutcome? posHealOutcome;

  const RemoteKeychainRecoveryState({
    this.status = RemoteKeychainRecoveryStatus.idle,
    this.restoredCount = 0,
    this.failedCount = 0,
    this.hasProductReactivationRequired = false,
    this.newestEventCreatedAt,
    this.selectedEventCreatedAt,
    this.isOlderRestore = false,
    this.failure,
    this.healOutcome,
    this.paymentPageHealOutcome,
    this.posHealOutcome,
  });
}
