import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/public/keychain_recovery_facade.dart';

enum RemoteKeychainRecoveryCheckStatus {
  requiresRelayDisclosure,
  latestManifestReady,
  olderManifestAvailable,
  noManifestFound,
  relaysUnavailable,
  noRecoverableManifest,
}

class RemoteKeychainRecoveryCheckResult {
  final RemoteKeychainRecoveryCheckStatus status;
  final KeychainManifestImportPlan? importPlan;
  final int? newestEventCreatedAt;
  final int? selectedEventCreatedAt;

  const RemoteKeychainRecoveryCheckResult._({
    required this.status,
    this.importPlan,
    this.newestEventCreatedAt,
    this.selectedEventCreatedAt,
  });

  const RemoteKeychainRecoveryCheckResult.requiresRelayDisclosure()
    : this._(status: RemoteKeychainRecoveryCheckStatus.requiresRelayDisclosure);

  factory RemoteKeychainRecoveryCheckResult.latestManifestReady({
    required KeychainManifestNostrImportResult manifestResult,
  }) {
    return RemoteKeychainRecoveryCheckResult._(
      status: RemoteKeychainRecoveryCheckStatus.latestManifestReady,
      importPlan: manifestResult.importPlan,
      newestEventCreatedAt: manifestResult.newestEventCreatedAt,
      selectedEventCreatedAt: manifestResult.selectedEventCreatedAt,
    );
  }

  factory RemoteKeychainRecoveryCheckResult.olderManifestAvailable({
    required KeychainManifestNostrImportResult manifestResult,
  }) {
    return RemoteKeychainRecoveryCheckResult._(
      status: RemoteKeychainRecoveryCheckStatus.olderManifestAvailable,
      importPlan: manifestResult.importPlan,
      newestEventCreatedAt: manifestResult.newestEventCreatedAt,
      selectedEventCreatedAt: manifestResult.selectedEventCreatedAt,
    );
  }

  const RemoteKeychainRecoveryCheckResult.noManifestFound()
    : this._(status: RemoteKeychainRecoveryCheckStatus.noManifestFound);

  const RemoteKeychainRecoveryCheckResult.relaysUnavailable()
    : this._(status: RemoteKeychainRecoveryCheckStatus.relaysUnavailable);

  const RemoteKeychainRecoveryCheckResult.noRecoverableManifest()
    : this._(status: RemoteKeychainRecoveryCheckStatus.noRecoverableManifest);
}

class RemoteKeychainRecoveryRestoreSummary {
  final int restoredCount;
  final int failedCount;
  final bool hasProductReactivationRequired;

  const RemoteKeychainRecoveryRestoreSummary({
    required this.restoredCount,
    required this.failedCount,
    required this.hasProductReactivationRequired,
  });

  factory RemoteKeychainRecoveryRestoreSummary.fromResult(
    KeychainRecoveryResult result,
  ) {
    return RemoteKeychainRecoveryRestoreSummary(
      restoredCount: result.walletOutcomes
          .where((outcome) => outcome.succeeded)
          .length,
      failedCount: result.walletOutcomes
          .where((outcome) => !outcome.succeeded)
          .length,
      hasProductReactivationRequired: result.hasProductReactivationRequired,
    );
  }
}
