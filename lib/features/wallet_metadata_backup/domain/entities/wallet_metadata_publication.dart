final class WalletMetadataRelayUrl {
  final Uri uri;

  WalletMetadataRelayUrl(String value) : uri = _parse(value);

  String get value => uri.toString();

  static Uri _parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'wss' ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        uri.hasQuery ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(value, 'value', 'must be a canonical wss URL');
    }
    return Uri(
      scheme: 'wss',
      host: uri.host.toLowerCase(),
      port: uri.hasPort && uri.port != 443 ? uri.port : null,
      path: uri.path == '/' ? '' : uri.path,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WalletMetadataRelayUrl && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'WalletMetadataRelayUrl(value: $value)';
}

enum WalletMetadataRelayReplicaStatus {
  chunksNotAccepted,
  rootNotAccepted,
  acceptedUnverified,
  verified,
}

final class WalletMetadataRelayReplicaOutcome {
  final WalletMetadataRelayUrl relayUrl;
  final WalletMetadataRelayReplicaStatus status;
  final int acceptedChunkCount;
  final int expectedChunkCount;
  final bool contactedRelay;

  WalletMetadataRelayReplicaOutcome({
    required this.relayUrl,
    required this.status,
    required this.acceptedChunkCount,
    required this.expectedChunkCount,
    required this.contactedRelay,
  }) {
    if (acceptedChunkCount < 0 ||
        expectedChunkCount < 0 ||
        acceptedChunkCount > expectedChunkCount) {
      throw ArgumentError('wallet metadata relay chunk counts are invalid');
    }
    final countsMatchStatus = switch (status) {
      WalletMetadataRelayReplicaStatus.chunksNotAccepted =>
        acceptedChunkCount < expectedChunkCount,
      WalletMetadataRelayReplicaStatus.rootNotAccepted ||
      WalletMetadataRelayReplicaStatus.acceptedUnverified ||
      WalletMetadataRelayReplicaStatus.verified =>
        acceptedChunkCount == expectedChunkCount,
    };
    if (!countsMatchStatus ||
        (!contactedRelay &&
            (acceptedChunkCount > 0 ||
                status == WalletMetadataRelayReplicaStatus.acceptedUnverified ||
                status == WalletMetadataRelayReplicaStatus.verified))) {
      throw ArgumentError('wallet metadata relay outcome is inconsistent');
    }
  }

  bool get rootAccepted =>
      status == WalletMetadataRelayReplicaStatus.acceptedUnverified ||
      status == WalletMetadataRelayReplicaStatus.verified;

  bool get verified => status == WalletMetadataRelayReplicaStatus.verified;
}

final class WalletMetadataSnapshotPublication {
  final List<WalletMetadataRelayReplicaOutcome> relayOutcomes;

  WalletMetadataSnapshotPublication({
    required List<WalletMetadataRelayReplicaOutcome> relayOutcomes,
  }) : relayOutcomes = List.unmodifiable(relayOutcomes) {
    if (this.relayOutcomes.isEmpty ||
        this.relayOutcomes.map((outcome) => outcome.relayUrl).toSet().length !=
            this.relayOutcomes.length) {
      throw ArgumentError.value(relayOutcomes, 'relayOutcomes');
    }
  }

  int get acceptedReplicaCount =>
      relayOutcomes.where((outcome) => outcome.rootAccepted).length;

  int get verifiedReplicaCount =>
      relayOutcomes.where((outcome) => outcome.verified).length;

  bool get contactedAnyRelay =>
      relayOutcomes.any((outcome) => outcome.contactedRelay);
}
