import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip85_entropy/bip85_entropy.dart';
import 'package:hex/hex.dart';

const _manifestEncryptionReservationId = 'keychain_manifest_encryption_key';

class DeriveKeychainManifestNostrEncryptionKeyUsecase {
  final Bip85RegistryFacade registry;

  const DeriveKeychainManifestNostrEncryptionKeyUsecase([
    this.registry = const Bip85RegistryFacade(),
  ]);

  KeychainManifestNostrEncryptionKey execute({
    required String xprvBase58,
    required String expectedParentFingerprint,
  }) {
    try {
      _validateParentFingerprint(
        xprvBase58: xprvBase58,
        expectedParentFingerprint: expectedParentFingerprint,
      );
      final reservation = _manifestEncryptionReservation();
      final derivation = Bip85Entropy.derive(
        xprvBase58: xprvBase58,
        application: CustomApplication.fromNumber(
          reservation.application.number,
        ),
        path: _registryRelativePath(reservation),
      );
      return KeychainManifestNostrEncryptionKey(
        HEX.encode(derivation.sublist(0, 32)),
      );
    } on KeychainManifestException {
      rethrow;
    } catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'failed to derive manifest encryption key',
        cause: e,
      );
    }
  }

  Bip85Reservation _manifestEncryptionReservation() {
    final reservation = registry.reservationById(
      _manifestEncryptionReservationId,
    );
    if (reservation == null) {
      throw KeychainManifestNostrEncryptionException(
        'manifest encryption reservation is missing',
      );
    }
    if (reservation.owner != Bip85ReservationOwner.keychainManifest ||
        reservation.purpose != Bip85ReservationPurpose.manifestEncryptionKey) {
      throw KeychainManifestNostrEncryptionException(
        'manifest encryption reservation is invalid',
      );
    }
    return reservation;
  }

  String _registryRelativePath(Bip85Reservation reservation) {
    final prefix = "${reservation.application.number}'/";
    if (!reservation.scope.exactPath.startsWith(prefix)) {
      throw KeychainManifestNostrEncryptionException(
        'manifest encryption reservation path is invalid',
      );
    }
    return reservation.scope.exactPath.substring(prefix.length);
  }

  void _validateParentFingerprint({
    required String xprvBase58,
    required String expectedParentFingerprint,
  }) {
    final expected = KeychainManifestFingerprint.normalize(
      expectedParentFingerprint,
    );
    final actual = bip32.Bip32Keys.fromBase58(xprvBase58).fingerprintHex;
    if (actual != expected) {
      throw KeychainManifestNostrEncryptionException(
        'manifest encryption xprv does not match parent fingerprint',
      );
    }
  }
}
