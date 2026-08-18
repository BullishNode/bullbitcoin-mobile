import 'package:bb_mobile/features/bip85_registry/domain/bip85_reservation.dart';
import 'package:bb_mobile/features/bip85_registry/domain/bip85_reservations.dart';

export 'package:bb_mobile/features/bip85_registry/domain/bip85_reservation.dart';

/// Read-only access to the application's static BIP85 reservation policy.
class Bip85RegistryFacade {
  const Bip85RegistryFacade();

  List<Bip85Reservation> get reservations => Bip85Reservations.all;

  Bip85WalletSeedReservation get btcpayWalletSeed =>
      Bip85Reservations.btcpayWalletSeed;

  Bip85WalletSeedReservation get lightningAddressWalletSeed =>
      Bip85Reservations.lightningAddressWalletSeed;

  Bip85WalletSeedReservation get paymentPageWalletSeed =>
      Bip85Reservations.paymentPageWalletSeed;

  Bip85WalletSeedReservation get pointOfSaleWalletSeed =>
      Bip85Reservations.posWalletSeed;

  // Registry-driven exclusion sets for the BIP85 next-index allocator and the
  // dev derivation screen: every reserved wallet-seed index/path is a product
  // spend seed that must never be allocated as a "next" dev derivation nor have
  // its entropy re-derived and exposed. Derived from the reservation list, so a
  // new wallet-seed reservation is covered automatically (KI-1/KI-2).
  Set<int> get reservedWalletSeedIndices => Set.unmodifiable(
    Bip85Reservations.all.whereType<Bip85WalletSeedReservation>().map(
      (reservation) => reservation.walletIndex,
    ),
  );

  Set<String> get reservedWalletSeedPaths => Set.unmodifiable(
    Bip85Reservations.all.whereType<Bip85WalletSeedReservation>().map(
      (reservation) => reservation.scope.exactPath,
    ),
  );

  int get nostrApplicationNumber => Bip85Reservations.nostrApplicationNumber;

  String get nostrUserKeyReservationId =>
      Bip85Reservations.nostrUserKeyReservationId;

  int get nostrUserKeyApplication => nostrApplicationNumber;

  int get nostrUserIdentityStart => Bip85Reservations.nostrUserIdentityStart;

  int get nostrUserIdentityEnd => Bip85Reservations.nostrUserIdentityEnd;

  int get nostrUserAccount => Bip85Reservations.nostrUserAccount;

  int get nostrAppReservedIdentityStart =>
      Bip85Reservations.nostrAppReservedIdentityStart;

  int get nostrAppReservedIdentityEnd =>
      Bip85Reservations.nostrAppReservedIdentityEnd;

  bool isNostrAppReservedIdentity(int identity) =>
      identity >= nostrAppReservedIdentityStart &&
      identity <= nostrAppReservedIdentityEnd;

  String nostrUserKeyPath(int identity) {
    if (identity < nostrUserIdentityStart ||
        identity > nostrUserIdentityEnd ||
        isNostrAppReservedIdentity(identity)) {
      throw ArgumentError.value(identity, 'identity');
    }
    return "$nostrUserKeyApplication'/$identity'/$nostrUserAccount'";
  }

  bool isNostrUserKeyPath(String path) {
    final normalized = path.trim();
    final identity = nostrUserKeyIdentity(normalized);
    return identity != null && nostrUserKeyPath(identity) == normalized;
  }

  int? nostrUserKeyIdentity(String path) {
    final normalized = path.trim();
    final parts = normalized.split('/');
    if (parts.length != 3 ||
        parts[0] != "$nostrUserKeyApplication'" ||
        parts[2] != "$nostrUserAccount'") {
      return null;
    }
    final identityPart = parts[1];
    if (!identityPart.endsWith("'") || identityPart.length == 1) return null;
    final identity = int.tryParse(
      identityPart.substring(0, identityPart.length - 1),
    );
    return identity != null &&
            identity >= nostrUserIdentityStart &&
            identity <= nostrUserIdentityEnd &&
            !isNostrAppReservedIdentity(identity)
        ? identity
        : null;
  }

  Bip85Reservation? reservationById(String id) {
    for (final reservation in reservations) {
      if (reservation.id == id) return reservation;
    }
    return null;
  }

  /// The reservation whose reserved path is exactly [path], or null when the
  /// path is not reserved.
  ///
  /// Callers classifying a stored derivation resolve it here rather than
  /// matching on labels or reservation ids: the reserved path is the only
  /// identity the registry guarantees.
  Bip85Reservation? reservationByExactPath(String path) {
    final normalized = path.trim();
    for (final reservation in reservations) {
      if (reservation.scope.matchesExactPath(normalized)) return reservation;
    }
    return null;
  }
}
