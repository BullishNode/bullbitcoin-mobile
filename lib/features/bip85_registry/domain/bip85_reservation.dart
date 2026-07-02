enum Bip85ReservationOwner { btcpay }

enum Bip85ReservationPurpose { walletSeed }

enum Bip85AllocationPolicy { blockExactPath }

enum Bip85ManifestPolicy { includeWhenMaterialized }

enum Bip85NetworkFamily { bitcoin, liquid }

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
  final int applicationNumber;
  final List<Bip85PathSegment> segments;
  final int walletIndex;

  Bip85ReservationScope._({required this.applicationNumber, required this.segments})
    : walletIndex = _requiredSegmentValue(segments, 'index');

  String get exactPath =>
      "$applicationNumber'/${segments.map((segment) => "${segment.value}'").join('/')}";

  bool matchesExactPath(String path) => exactPath == path;

  int segmentValue(String name) {
    for (final segment in segments) {
      if (segment.name == name) return segment.value;
    }
    throw StateError('Unknown BIP85 reservation path segment: $name');
  }

  static int _requiredSegmentValue(
    List<Bip85PathSegment> segments,
    String name,
  ) {
    for (final segment in segments) {
      if (segment.name == name) return segment.value;
    }
    throw ArgumentError(
      "BIP85 reservation scope requires an '$name' path segment",
    );
  }
}

class Bip85WalletHint {
  final String id;
  final Bip85NetworkFamily networkFamily;
  final String purpose;

  const Bip85WalletHint({
    required this.id,
    required this.networkFamily,
    required this.purpose,
  });
}

class Bip85ReservationHints {
  final List<Bip85WalletHint> wallets;

  const Bip85ReservationHints({this.wallets = const []});
}

class Bip85Reservation {
  final String id;
  final Bip85ReservationOwner owner;
  final Bip85ReservationPurpose purpose;
  final Bip85ApplicationSpec application;
  final Bip85ReservationScope scope;
  final Bip85AllocationPolicy allocation;
  final Bip85ManifestPolicy manifest;
  final Bip85ReservationHints hints;

  Bip85Reservation({
    required this.id,
    required this.owner,
    required this.purpose,
    required this.application,
    required List<Bip85PathSegment> segments,
    required this.allocation,
    required this.manifest,
    required this.hints,
  }) : scope = Bip85ReservationScope._(
         applicationNumber: application.number,
         segments: segments,
       );

  int get walletIndex => scope.walletIndex;
}
