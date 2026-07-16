enum WalletMetadataPublishStatus {
  notReady,
  initialEmpty,
  unchanged,
  notAccepted,
  acceptedUnverified,
  verified,
}

final class WalletMetadataPublishOutcome {
  final WalletMetadataPublishStatus status;
  final int acceptedReplicaCount;
  final int verifiedReplicaCount;
  final String? rootEventId;

  WalletMetadataPublishOutcome({
    required this.status,
    this.acceptedReplicaCount = 0,
    this.verifiedReplicaCount = 0,
    this.rootEventId,
  }) {
    if (acceptedReplicaCount < 0 ||
        verifiedReplicaCount < 0 ||
        verifiedReplicaCount > acceptedReplicaCount) {
      throw ArgumentError('wallet metadata publication counts are invalid');
    }
    final hasPublishedRoot = switch (status) {
      WalletMetadataPublishStatus.notAccepted ||
      WalletMetadataPublishStatus.acceptedUnverified ||
      WalletMetadataPublishStatus.verified => true,
      WalletMetadataPublishStatus.notReady ||
      WalletMetadataPublishStatus.initialEmpty ||
      WalletMetadataPublishStatus.unchanged => false,
    };
    if (hasPublishedRoot != (rootEventId != null)) {
      throw ArgumentError('wallet metadata publication root id is invalid');
    }
    final countsMatchStatus = switch (status) {
      WalletMetadataPublishStatus.notReady ||
      WalletMetadataPublishStatus.initialEmpty ||
      WalletMetadataPublishStatus.unchanged ||
      WalletMetadataPublishStatus.notAccepted =>
        acceptedReplicaCount == 0 && verifiedReplicaCount == 0,
      WalletMetadataPublishStatus.acceptedUnverified =>
        acceptedReplicaCount > 0 && verifiedReplicaCount == 0,
      WalletMetadataPublishStatus.verified => verifiedReplicaCount > 0,
    };
    if (!countsMatchStatus) {
      throw ArgumentError('wallet metadata publication status is invalid');
    }
  }
}
