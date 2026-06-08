import 'package:bb_mobile/features/bip85_registry/domain/bip85_reservation.dart';
import 'package:bb_mobile/features/bip85_registry/domain/bip85_reservations.dart';

export 'package:bb_mobile/features/bip85_registry/domain/bip85_reservation.dart';

class Bip85RegistryFacade {
  const Bip85RegistryFacade();

  List<Bip85Reservation> get reservations => Bip85Reservations.all;

  Bip85Reservation get btcpayWalletSeed => Bip85Reservations.btcpayWalletSeed;

  Bip85Reservation get lightningAddressWalletSeed =>
      Bip85Reservations.lightningAddressWalletSeed;

  Bip85Reservation? reservationById(String id) {
    for (final reservation in reservations) {
      if (reservation.id == id) return reservation;
    }
    return null;
  }

  Bip85Reservation? reservationByExactPath(String path) {
    for (final reservation in reservations) {
      if (reservation.scope.matchesExactPath(path)) return reservation;
    }
    return null;
  }

  bool isExactPathReservedForManualAllocation(String path) {
    final reservation = reservationByExactPath(path);
    return reservation?.allocation == Bip85AllocationPolicy.blockExactPath;
  }
}
