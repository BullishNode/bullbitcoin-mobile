import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';

class KeychainManifestEntry {
  final String entryId;
  final String parentFingerprint;
  final String bip85DerivationPath;
  final String reservationId;
  final String entryType;
  final String ownerFeature;
  final int bip85Application;
  final int bip85Index;
  final int createdAt;
  final int updatedAt;

  KeychainManifestEntry({
    String? entryId,
    required String parentFingerprint,
    required String bip85DerivationPath,
    required this.reservationId,
    required this.entryType,
    required this.ownerFeature,
    required this.bip85Application,
    required this.bip85Index,
    required this.createdAt,
    required this.updatedAt,
  }) : parentFingerprint = KeychainManifestFingerprint.normalize(
         parentFingerprint,
       ),
       bip85DerivationPath = KeychainManifestBip85Path.normalize(
         bip85DerivationPath,
       ),
       entryId =
           entryId ??
           KeychainManifestEntryId.fromIdentity(
             parentFingerprint: parentFingerprint,
             bip85DerivationPath: bip85DerivationPath,
           ) {
    final expectedEntryId = KeychainManifestEntryId.fromIdentity(
      parentFingerprint: this.parentFingerprint,
      bip85DerivationPath: this.bip85DerivationPath,
    );
    if (this.entryId != expectedEntryId) {
      throw KeychainManifestInvalidEntryException(
        'entry id must match parent fingerprint and BIP85 path',
      );
    }
    if (reservationId.trim().isEmpty) {
      throw KeychainManifestInvalidEntryException('reservation id is required');
    }
    if (entryType.trim().isEmpty) {
      throw KeychainManifestInvalidEntryException('entry type is required');
    }
    if (ownerFeature.trim().isEmpty) {
      throw KeychainManifestInvalidEntryException('owner feature is required');
    }
    if (bip85Application < 0 || bip85Index < 0) {
      throw KeychainManifestInvalidEntryException(
        'BIP85 application and index must be non-negative',
      );
    }
    if (createdAt < 0 || updatedAt < 0) {
      throw KeychainManifestInvalidEntryException(
        'timestamps must be non-negative',
      );
    }
  }

  KeychainManifestEntryIdentity get identity => KeychainManifestEntryIdentity(
    parentFingerprint: parentFingerprint,
    bip85DerivationPath: bip85DerivationPath,
  );

  /// Compares durable identity fields only. Descriptive metadata
  /// (reservationId, entryType, ownerFeature) and path-derived numbers are
  /// deliberately excluded: entries are append-only, so on an identity-equal
  /// record the stored row wins and a metadata rename must never turn a
  /// re-pair into a conflict.
  bool sameRecordAs(KeychainManifestEntry other) {
    return parentFingerprint == other.parentFingerprint &&
        bip85DerivationPath == other.bip85DerivationPath;
  }
}

/// A wallet binding deliberately carries no wallet-purpose field: the network
/// family is derivable from [network], and feature ownership lives on the
/// entry's `ownerFeature`.
class KeychainManifestWalletMaterialization {
  final String walletId;
  final String entryId;
  final String childSeedFingerprint;
  final String network;
  final String scriptType;
  final int createdAt;
  final int updatedAt;

  KeychainManifestWalletMaterialization({
    required this.walletId,
    required this.entryId,
    required String childSeedFingerprint,
    required this.network,
    required this.scriptType,
    required this.createdAt,
    required this.updatedAt,
  }) : childSeedFingerprint = KeychainManifestFingerprint.normalize(
         childSeedFingerprint,
       ) {
    if (walletId.trim().isEmpty) {
      throw KeychainManifestInvalidEntryException('wallet id is required');
    }
    if (entryId.trim().isEmpty) {
      throw KeychainManifestInvalidEntryException('entry id is required');
    }
    if (network.trim().isEmpty) {
      throw KeychainManifestInvalidEntryException('network is required');
    }
    if (scriptType.trim().isEmpty) {
      throw KeychainManifestInvalidEntryException('script type is required');
    }
    if (createdAt < 0 || updatedAt < 0) {
      throw KeychainManifestInvalidEntryException(
        'timestamps must be non-negative',
      );
    }
  }

  /// Compares durable identity fields only: the wallet binding is identified
  /// by wallet id, entry id, child seed fingerprint, network, and script
  /// type. Descriptive metadata mismatches on an identity-equal record are
  /// not a conflict; the stored row wins (append-only, no update).
  bool sameRecordAs(KeychainManifestWalletMaterialization other) {
    return walletId == other.walletId &&
        entryId == other.entryId &&
        childSeedFingerprint == other.childSeedFingerprint &&
        network == other.network &&
        scriptType == other.scriptType;
  }
}

class KeychainManifestWalletMaterializationRecord {
  final KeychainManifestEntry entry;
  final KeychainManifestWalletMaterialization walletMaterialization;

  const KeychainManifestWalletMaterializationRecord({
    required this.entry,
    required this.walletMaterialization,
  });

  String get walletId => walletMaterialization.walletId;
  KeychainManifestEntryIdentity get identity => entry.identity;

  bool sameRecordAs(KeychainManifestWalletMaterializationRecord other) {
    return entry.sameRecordAs(other.entry) &&
        walletMaterialization.sameRecordAs(other.walletMaterialization);
  }
}

enum KeychainManifestNostrKeyKind { reserved, userGenerated }

class KeychainManifestNostrKeyMaterialization {
  /// Upper bound on the key's name (its `purpose`). Named so an input field can
  /// enforce the same bound the entity does instead of repeating the number.
  static const maxPurposeLength = 80;

  /// Upper bound on the optional free-form description. Long enough for a
  /// sentence of context, short enough to stay inside the manifest file's
  /// per-field string cap.
  static const maxDescriptionLength = 200;

  /// C0 control characters and DEL, rejected in user-authored metadata so
  /// a stored value can never smuggle newlines or terminal escapes into a
  /// list row, a backup file, or a log line.
  static final controlCharacterPattern = RegExp(r'[\u0000-\u001F\u007F]');

  final String entryId;
  final String publicKeyHex;
  final KeychainManifestNostrKeyKind keyKind;
  final String purpose;

  /// Optional free-form context for a user key. An empty or whitespace-only
  /// value is absent, never a stored empty string, so "no description" has a
  /// single representation in the database and in the backup file.
  final String? description;
  final int createdAt;
  final int updatedAt;

  KeychainManifestNostrKeyMaterialization({
    required this.entryId,
    required String publicKeyHex,
    required this.keyKind,
    required String purpose,
    String? description,
    required this.createdAt,
    required this.updatedAt,
  }) : publicKeyHex = publicKeyHex.toLowerCase(),
       purpose = purpose.trim(),
       description = normalizeDescription(description) {
    if (entryId.trim().isEmpty) {
      throw KeychainManifestInvalidEntryException('entry id is required');
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(publicKeyHex)) {
      throw KeychainManifestInvalidEntryException(
        'Nostr public key must be 32-byte hex',
      );
    }
    if (this.purpose.isEmpty || this.purpose.length > maxPurposeLength) {
      throw KeychainManifestInvalidEntryException(
        'Nostr key purpose must contain 1 to $maxPurposeLength characters',
      );
    }
    if (this.purpose.contains(RegExp(r'[\u0000-\u001F\u007F]'))) {
      throw KeychainManifestInvalidEntryException(
        'Nostr key purpose contains a control character',
      );
    }
    final normalizedDescription = this.description;
    if (normalizedDescription != null) {
      if (normalizedDescription.length > maxDescriptionLength) {
        throw KeychainManifestInvalidEntryException(
          'Nostr key description must contain at most '
          '$maxDescriptionLength characters',
        );
      }
      if (normalizedDescription.contains(controlCharacterPattern)) {
        throw KeychainManifestInvalidEntryException(
          'Nostr key description contains a control character',
        );
      }
    }
    if (createdAt < 0 || updatedAt < 0) {
      throw KeychainManifestInvalidEntryException(
        'timestamps must be non-negative',
      );
    }
  }

  /// Trims a candidate description and collapses an empty result to null.
  ///
  /// Exposed so the persistence and file layers normalize identically before
  /// comparing a stored value with an incoming one.
  static String? normalizeDescription(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool sameIdentityAs(KeychainManifestNostrKeyMaterialization other) {
    return entryId == other.entryId &&
        publicKeyHex == other.publicKeyHex &&
        keyKind == other.keyKind &&
        createdAt == other.createdAt;
  }

  bool sameRecordAs(KeychainManifestNostrKeyMaterialization other) {
    return sameIdentityAs(other) &&
        purpose == other.purpose &&
        updatedAt == other.updatedAt;
  }
}

class KeychainManifestNostrKeyRecord {
  final KeychainManifestEntry entry;
  final KeychainManifestNostrKeyMaterialization nostrKeyMaterialization;

  const KeychainManifestNostrKeyRecord({
    required this.entry,
    required this.nostrKeyMaterialization,
  });

  String get entryId => entry.entryId;

  bool sameRecordAs(KeychainManifestNostrKeyRecord other) {
    return entry.sameRecordAs(other.entry) &&
        nostrKeyMaterialization.sameRecordAs(other.nostrKeyMaterialization);
  }
}

class KeychainManifestEntryIdentity {
  final String parentFingerprint;
  final String bip85DerivationPath;

  KeychainManifestEntryIdentity({
    required String parentFingerprint,
    required String bip85DerivationPath,
  }) : parentFingerprint = KeychainManifestFingerprint.normalize(
         parentFingerprint,
       ),
       bip85DerivationPath = KeychainManifestBip85Path.normalize(
         bip85DerivationPath,
       );

  String get entryId => KeychainManifestEntryId.fromIdentity(
    parentFingerprint: parentFingerprint,
    bip85DerivationPath: bip85DerivationPath,
  );
}

class KeychainManifestEntryId {
  const KeychainManifestEntryId._();

  static String fromIdentity({
    required String parentFingerprint,
    required String bip85DerivationPath,
  }) {
    final fingerprint = KeychainManifestFingerprint.normalize(
      parentFingerprint,
    );
    final path = KeychainManifestBip85Path.normalize(bip85DerivationPath);
    return '$fingerprint:$path';
  }
}

class KeychainManifestFingerprint {
  static final _pattern = RegExp(r'^[0-9a-fA-F]{8}$');

  const KeychainManifestFingerprint._();

  static String normalize(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_pattern.hasMatch(normalized)) {
      throw KeychainManifestInvalidEntryException(
        'fingerprint must be 8 hex characters',
      );
    }
    return normalized;
  }
}

class KeychainManifestBip85Path {
  static final _pattern = RegExp(r"^[0-9]+'(?:/[0-9]+')+$");
  static final _segmentPattern = RegExp(r"([0-9]+)'");

  const KeychainManifestBip85Path._();

  static String normalize(String value) {
    final normalized = value.trim();
    if (!_pattern.hasMatch(normalized)) {
      throw KeychainManifestInvalidEntryException(
        'BIP85 path must be a registry-relative hardened path',
      );
    }
    final segments = <String>[];
    for (final match in _segmentPattern.allMatches(normalized)) {
      final segment = int.tryParse(match.group(1)!);
      if (segment == null || segment < 0 || segment > 0x7fffffff) {
        throw KeychainManifestInvalidEntryException(
          'BIP85 path segment is invalid',
        );
      }
      segments.add("$segment'");
    }
    return segments.join('/');
  }
}
