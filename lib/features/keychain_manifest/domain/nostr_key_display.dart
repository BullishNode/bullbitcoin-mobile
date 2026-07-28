import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';

/// The app-owned role behind a system Nostr key, or [none] for a user key.
///
/// This enum is the presentation contract: a UI layer maps it to localized
/// labels and to what a row may offer, and never re-derives a role from
/// user-editable text such as `purpose`.
enum KeychainManifestNostrSystemKind {
  /// Signs the encrypted wallet-metadata backup.
  metadataBackup,

  /// Authenticates the device to the Bullnym server.
  bullnymAuth,

  /// Proves ownership of a public NIP-05 nym.
  nip05Verification,

  /// A retired role that must never be shown. Its reservation no longer
  /// exists, so it is recognized by the historical identity it was written
  /// with; rows and backup content keep it untouched.
  obsoleteWalletMetadataSigning,

  /// No app-owned role resolved: a key the user created, or a reserved key at
  /// a path this build does not reserve. [KeychainManifestNostrKeyDisplay
  /// .isSystem] still distinguishes the two.
  none,
}

/// Classification of a stored Nostr key for display purposes.
///
/// Derived from the record plus the BIP85 registry only. Nothing here reads or
/// interprets user-authored metadata.
class KeychainManifestNostrKeyDisplay {
  /// The reservation id the retired wallet-metadata signing key was recorded
  /// under before it was removed from the registry.
  static const obsoleteWalletMetadataSigningReservationId =
      'wallet_metadata_signing_key';

  /// The exact path the retired wallet-metadata signing key occupied, under the
  /// superseded application number `9000'`. Kept here rather than in the
  /// registry: the reservation is gone and must never be re-derivable, but a
  /// database written before its removal can still hold a row at this path.
  static const obsoleteWalletMetadataSigningPath = "9000'/4'/1'";

  /// Whether the key belongs to the app rather than the user.
  final bool isSystem;

  final KeychainManifestNostrSystemKind systemKind;

  const KeychainManifestNostrKeyDisplay({
    required this.isSystem,
    required this.systemKind,
  });

  factory KeychainManifestNostrKeyDisplay.of(
    KeychainManifestNostrKeyRecord record, {
    Bip85RegistryFacade registry = const Bip85RegistryFacade(),
  }) {
    final isSystem =
        record.nostrKeyMaterialization.keyKind ==
        KeychainManifestNostrKeyKind.reserved;
    return KeychainManifestNostrKeyDisplay(
      isSystem: isSystem,
      systemKind: isSystem
          ? _systemKind(record, registry)
          : KeychainManifestNostrSystemKind.none,
    );
  }

  /// Whether this key is a retired role that no listing may surface.
  bool get isObsolete =>
      systemKind ==
      KeychainManifestNostrSystemKind.obsoleteWalletMetadataSigning;

  static KeychainManifestNostrSystemKind _systemKind(
    KeychainManifestNostrKeyRecord record,
    Bip85RegistryFacade registry,
  ) {
    final path = record.entry.bip85DerivationPath;
    if (path == obsoleteWalletMetadataSigningPath ||
        record.entry.reservationId ==
            obsoleteWalletMetadataSigningReservationId) {
      return KeychainManifestNostrSystemKind.obsoleteWalletMetadataSigning;
    }
    final reservation = registry.reservationByExactPath(path);
    return switch (reservation?.id) {
      'nostr_wallet_backup_key' =>
        KeychainManifestNostrSystemKind.metadataBackup,
      'nostr_bullnym_server_auth_key' =>
        KeychainManifestNostrSystemKind.bullnymAuth,
      'nostr_nip05_public_nym_verification_key' =>
        KeychainManifestNostrSystemKind.nip05Verification,
      // A reserved key at a path this build does not reserve: treated as an
      // unknown system key rather than promoted to a user key, so it stays
      // non-editable.
      _ => KeychainManifestNostrSystemKind.none,
    };
  }
}
