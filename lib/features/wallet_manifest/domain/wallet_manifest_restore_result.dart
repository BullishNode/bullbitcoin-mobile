import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';

enum WalletManifestRestoreStatus {
  created,
  alreadyPresent,
  skippedWrongRoot,
  failed,
}

enum WalletManifestRestoreFailureStage {
  deriveMnemonic,
  createSeed,
  createWallet,
  recordBip85,
  recordOrigin,
}

class WalletManifestSnapshotRestoreResult {
  final List<WalletManifestAccountRestoreOutcome> outcomes;

  const WalletManifestSnapshotRestoreResult({required this.outcomes});

  List<WalletManifestAccountRestoreOutcome> get restored => outcomes
      .where((outcome) => outcome.status == WalletManifestRestoreStatus.created)
      .toList(growable: false);

  List<WalletManifestAccountRestoreOutcome> get alreadyPresent => outcomes
      .where(
        (outcome) =>
            outcome.status == WalletManifestRestoreStatus.alreadyPresent,
      )
      .toList(growable: false);

  List<WalletManifestAccountRestoreOutcome> get skipped => outcomes
      .where(
        (outcome) =>
            outcome.status == WalletManifestRestoreStatus.skippedWrongRoot,
      )
      .toList(growable: false);

  List<WalletManifestAccountRestoreOutcome> get failed => outcomes
      .where((outcome) => outcome.status == WalletManifestRestoreStatus.failed)
      .toList(growable: false);
}

class WalletManifestAccountRestoreOutcome {
  final WalletManifestAccount account;
  final WalletManifestRestoreStatus status;
  final String? walletId;
  final String? actualLabel;
  final WalletManifestRestoreFailureStage? failureStage;
  final Object? cause;
  final bool walletStateChanged;

  const WalletManifestAccountRestoreOutcome({
    required this.account,
    required this.status,
    this.walletId,
    this.actualLabel,
    this.failureStage,
    this.cause,
    this.walletStateChanged = false,
  });
}
