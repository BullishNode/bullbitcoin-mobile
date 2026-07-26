import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';

enum KeychainRecoveryWalletRestoreStatus {
  created,
  alreadyPresent,
  requiresProductReactivation,
  skippedUnsupported,
  failedParentFingerprintMismatch,
  failedChildSeedFingerprintMismatch,
  failedInvalidImportPlan,
  failedWalletCreation,
  failedManifestRecord,
  failedConflict,
  // The recovery time budget elapsed before this entry was materialized, so it
  // was never attempted. Not a success; callers keep what restored and report
  // the remainder as failures (a partial restore).
  skippedTimeBudgetExpired,
}

class KeychainRecoveryWalletIntent {
  final String entryId;
  final String reservationId;
  final String bip85DerivationPath;
  final String walletId;
  final String childSeedFingerprint;
  final Network network;
  final ScriptType scriptType;

  const KeychainRecoveryWalletIntent({
    required this.entryId,
    required this.reservationId,
    required this.bip85DerivationPath,
    required this.walletId,
    required this.childSeedFingerprint,
    required this.network,
    required this.scriptType,
  });

  String get materializationKey => '$entryId:$walletId';
}

class KeychainRecoveryWalletRestoreOutcome {
  final KeychainRecoveryWalletIntent intent;
  final KeychainRecoveryWalletRestoreStatus status;
  final String? materializedWalletId;
  final bool created;

  const KeychainRecoveryWalletRestoreOutcome({
    required this.intent,
    required this.status,
    this.materializedWalletId,
    this.created = false,
  });

  String get walletId => materializedWalletId ?? intent.walletId;

  bool get succeeded {
    return switch (status) {
      KeychainRecoveryWalletRestoreStatus.created ||
      KeychainRecoveryWalletRestoreStatus.alreadyPresent ||
      KeychainRecoveryWalletRestoreStatus.requiresProductReactivation => true,
      _ => false,
    };
  }
}

class KeychainRecoveryResult {
  final List<KeychainRecoveryWalletRestoreOutcome> walletOutcomes;
  final List<KeychainRecoveryNostrKeyRestoreOutcome> nostrKeyOutcomes;

  const KeychainRecoveryResult({
    required this.walletOutcomes,
    this.nostrKeyOutcomes = const [],
  });

  bool get hasFailures =>
      walletOutcomes.any((outcome) => !outcome.succeeded) ||
      nostrKeyOutcomes.any((outcome) => !outcome.succeeded);

  /// Number of wallets actually restored (created or already present).
  int get restoredCount => walletOutcomes.where((o) => o.succeeded).length;

  int get restoredNostrKeyCount =>
      nostrKeyOutcomes.where((outcome) => outcome.succeeded).length;

  /// True when nothing was restored - an empty import plan or an all-failed
  /// run. Consumers MUST NOT treat this as a plain success: `hasFailures` is
  /// false for an empty plan, so a "restored" screen with zero wallets would
  /// otherwise be shown (PR06 I-A; the sink is closed at PR22, R2-P22a).
  bool get restoredNothing => restoredCount + restoredNostrKeyCount == 0;

  bool get hasProductReactivationRequired {
    return walletOutcomes.any(
      (outcome) =>
          outcome.status ==
          KeychainRecoveryWalletRestoreStatus.requiresProductReactivation,
    );
  }

  List<KeychainRecoveryWalletRestoreOutcome>
  get productReactivationRequiredOutcomes {
    return walletOutcomes
        .where(
          (outcome) =>
              outcome.status ==
              KeychainRecoveryWalletRestoreStatus.requiresProductReactivation,
        )
        .toList(growable: false);
  }
}

enum KeychainRecoveryNostrKeyRestoreStatus {
  created,
  alreadyPresent,
  failedVerification,
  failedInvalidImportPlan,
  failedManifestRecord,
  skippedTimeBudgetExpired,
}

class KeychainRecoveryNostrKeyIntent {
  final String entryId;
  final String reservationId;
  final String bip85DerivationPath;
  final String publicKeyHex;
  final KeychainManifestNostrKeyKind keyKind;
  final String purpose;

  const KeychainRecoveryNostrKeyIntent({
    required this.entryId,
    required this.reservationId,
    required this.bip85DerivationPath,
    required this.publicKeyHex,
    required this.keyKind,
    required this.purpose,
  });
}

class KeychainRecoveryNostrKeyRestoreOutcome {
  final KeychainRecoveryNostrKeyIntent intent;
  final KeychainRecoveryNostrKeyRestoreStatus status;

  const KeychainRecoveryNostrKeyRestoreOutcome({
    required this.intent,
    required this.status,
  });

  bool get succeeded =>
      status == KeychainRecoveryNostrKeyRestoreStatus.created ||
      status == KeychainRecoveryNostrKeyRestoreStatus.alreadyPresent;
}
