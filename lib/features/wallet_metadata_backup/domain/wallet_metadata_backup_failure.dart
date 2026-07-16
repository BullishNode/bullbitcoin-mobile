import 'package:bb_mobile/core/failures/failure.dart';

sealed class WalletMetadataBackupFailure extends Failure {
  const WalletMetadataBackupFailure([super.logMessage]);
}

final class WalletMetadataBackupStorageFailure
    extends WalletMetadataBackupFailure {
  const WalletMetadataBackupStorageFailure([super.logMessage]);
}

final class WalletMetadataBackupContributorFailure
    extends WalletMetadataBackupFailure {
  final String contributorType;

  const WalletMetadataBackupContributorFailure(this.contributorType)
    : super('Wallet metadata contributor failed');
}

final class WalletMetadataBackupKeyFailure extends WalletMetadataBackupFailure {
  const WalletMetadataBackupKeyFailure()
    : super('Wallet metadata key derivation failed');
}

final class WalletMetadataBackupEncodingFailure
    extends WalletMetadataBackupFailure {
  const WalletMetadataBackupEncodingFailure()
    : super('Wallet metadata snapshot encoding failed');
}

final class WalletMetadataBackupRecordTooLargeFailure
    extends WalletMetadataBackupFailure {
  final String recordType;
  final int maxFrameBytes;

  const WalletMetadataBackupRecordTooLargeFailure({
    required this.recordType,
    required this.maxFrameBytes,
  }) : super('One wallet metadata record does not fit in a Nostr event');
}

final class WalletMetadataBackupChunkLimitFailure
    extends WalletMetadataBackupFailure {
  final int maxChunks;

  const WalletMetadataBackupChunkLimitFailure({required this.maxChunks})
    : super('Wallet metadata snapshot exceeds the chunk limit');
}

final class WalletMetadataBackupRootTooLargeFailure
    extends WalletMetadataBackupFailure {
  final int frameBytes;
  final int maxFrameBytes;

  const WalletMetadataBackupRootTooLargeFailure({
    required this.frameBytes,
    required this.maxFrameBytes,
  }) : super('Wallet metadata root does not fit in a Nostr event');
}

final class WalletMetadataBackupResourceLimitFailure
    extends WalletMetadataBackupFailure {
  const WalletMetadataBackupResourceLimitFailure()
    : super('Wallet metadata snapshot exceeds a resource limit');
}

final class WalletMetadataBackupRelayFailure
    extends WalletMetadataBackupFailure {
  const WalletMetadataBackupRelayFailure()
    : super('Wallet metadata relay operation failed');
}

final class WalletMetadataBackupRemoteHeadFailure
    extends WalletMetadataBackupFailure {
  const WalletMetadataBackupRemoteHeadFailure()
    : super('Wallet metadata remote head is not safe to replace');
}

final class WalletMetadataBackupUpdateRequiredFailure
    extends WalletMetadataBackupFailure {
  const WalletMetadataBackupUpdateRequiredFailure()
    : super('Wallet metadata backup requires a newer app version');
}

final class WalletMetadataBackupClockFailure
    extends WalletMetadataBackupFailure {
  const WalletMetadataBackupClockFailure()
    : super('Wallet metadata publication clock or revision is exhausted');
}
