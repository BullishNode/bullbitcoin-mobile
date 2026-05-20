import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';

enum ExternalReceiveWalletRestoreOutcomeStatus {
  existing,
  repaired,
  created,
  createdWithMetadataFailure,
  failed,
}

enum ExternalReceiveWalletRestoreFailureReason {
  noDefaultWallet,
  alreadyExistsRace,
  metadataUpdateFailed,
  walletCreationFailed,
}

class ExternalReceiveWalletRestoreOutcome {
  final ExternalReceiveWalletAccountKey accountKey;
  final ExternalReceiveWalletRestoreOutcomeStatus status;
  final ExternalReceiveWalletRestoreFailureReason? failureReason;

  const ExternalReceiveWalletRestoreOutcome({
    required this.accountKey,
    required this.status,
    this.failureReason,
  });

  bool get changedLocalState =>
      status == ExternalReceiveWalletRestoreOutcomeStatus.repaired ||
      status == ExternalReceiveWalletRestoreOutcomeStatus.created ||
      status ==
          ExternalReceiveWalletRestoreOutcomeStatus.createdWithMetadataFailure;
}
