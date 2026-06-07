import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';

const _walletManifestReservationId = 'nostr_wallet_manifest_key';
const _bullnymServerAuthReservationId = 'nostr_bullnym_server_auth_key';

enum NostrIdentityRole { walletManifest, bullnymServerAuth }

class DeriveNostrIdentityHandleUsecase {
  final Bip85RegistryFacade _registry;

  const DeriveNostrIdentityHandleUsecase([
    this._registry = const Bip85RegistryFacade(),
  ]);

  NostrKeychainHandle execute({
    required String xprvBase58,
    required NostrIdentityRole role,
  }) {
    return _deriveFromReservation(
      xprvBase58: xprvBase58,
      reservationId: _reservationIdForRole(role),
    );
  }

  String _reservationIdForRole(NostrIdentityRole role) {
    return switch (role) {
      NostrIdentityRole.walletManifest => _walletManifestReservationId,
      NostrIdentityRole.bullnymServerAuth => _bullnymServerAuthReservationId,
    };
  }

  NostrKeychainHandle _deriveFromReservation({
    required String xprvBase58,
    required String reservationId,
  }) {
    final reservation = _registry.reservationById(reservationId);
    if (reservation == null) {
      throw StateError('Unknown Nostr BIP85 reservation: $reservationId');
    }
    _validateNostrReservation(reservation);
    return NostrKeychainHandle.deriveFromBip85Path(
      xprvBase58: xprvBase58,
      hardenedPath: reservation.scope.exactPath,
    );
  }

  void _validateNostrReservation(Bip85Reservation reservation) {
    if (reservation.application.number != nostrBip85Application) {
      throw StateError(
        'Expected Nostr BIP85 application $nostrBip85Application, '
        'got ${reservation.application.number}',
      );
    }
    if (reservation.owner != Bip85ReservationOwner.nostr) {
      throw StateError('Expected a Nostr-owned BIP85 reservation');
    }
  }
}
