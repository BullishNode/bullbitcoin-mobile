enum Bip85ReservationOwner { btcpay, lightningAddress, paymentPage, nostr }

enum Bip85ReservationPurpose { walletSeed, nonWalletNostrKey }

enum Bip85AllocationPolicy { blockExactPath }

class Bip85ApplicationSpec {
  final int number;
  final String name;
  final bool standard;

  const Bip85ApplicationSpec({
    required this.number,
    required this.name,
    required this.standard,
  });
}

class Bip85PathSegment {
  final String name;
  final int value;

  const Bip85PathSegment({required this.name, required this.value});
}

class Bip85ReservationScope {
  final String exactPath;
  final List<Bip85PathSegment> segments;

  const Bip85ReservationScope({
    required this.exactPath,
    required this.segments,
  });

  bool matchesExactPath(String path) => exactPath == path;

  int segmentValue(String name) {
    for (final segment in segments) {
      if (segment.name == name) return segment.value;
    }
    throw StateError('Unknown BIP85 reservation path segment: $name');
  }
}

class Bip85WalletMaterializationPolicy {
  final int count;
  final Map<String, String> networkNameByEnvironment;
  final String walletPurpose;
  final String scriptType;
  final bool requiresProductReactivationOnRecovery;

  const Bip85WalletMaterializationPolicy({
    required this.count,
    required this.networkNameByEnvironment,
    required this.walletPurpose,
    required this.scriptType,
    this.requiresProductReactivationOnRecovery = false,
  });

  Set<String> get networkNames => networkNameByEnvironment.values.toSet();

  String networkNameForEnvironment(String environmentName) {
    final networkName = networkNameByEnvironment[environmentName];
    if (networkName == null) {
      throw StateError(
        'Unknown wallet materialization environment: $environmentName',
      );
    }
    return networkName;
  }
}

class Bip85Reservation {
  final String id;
  final String deterministicAlias;
  final Bip85ReservationOwner owner;
  final Bip85ReservationPurpose purpose;
  final Bip85ApplicationSpec application;
  final Bip85ReservationScope scope;
  final Bip85AllocationPolicy allocation;
  final Bip85WalletMaterializationPolicy? walletMaterializationPolicy;

  const Bip85Reservation({
    required this.id,
    required this.deterministicAlias,
    required this.owner,
    required this.purpose,
    required this.application,
    required this.scope,
    required this.allocation,
    this.walletMaterializationPolicy,
  });
}
