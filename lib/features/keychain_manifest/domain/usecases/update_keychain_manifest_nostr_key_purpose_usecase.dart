// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';

class UpdateKeychainManifestNostrKeyPurposeUsecase {
  final KeychainManifestEntryRepository _repository;
  final Bip85RegistryFacade _registry;
  final Clock _clock;

  const UpdateKeychainManifestNostrKeyPurposeUsecase({
    required KeychainManifestEntryRepository repository,
    Bip85RegistryFacade registry = const Bip85RegistryFacade(),
    Clock clock = const SystemClock(),
  }) : _repository = repository,
       _registry = registry,
       _clock = clock;

  /// Updates a user key's editable metadata.
  ///
  /// A null [purpose] leaves the stored purpose unchanged. A null
  /// [description] leaves the stored description unchanged; an empty or
  /// whitespace-only [description] clears it, mirroring the entity's rule that
  /// an empty description is an absent one. Both fields are written together so
  /// a single edit advances one revision instead of two.
  Future<void> execute({
    required String parentFingerprint,
    required String entryId,
    String? purpose,
    String? description,
    DateTime? now,
  }) async {
    final records = await _repository.fetchNostrKeyRecordsByParentFingerprint(
      parentFingerprint,
    );
    KeychainManifestNostrKeyRecord? record;
    for (final candidate in records) {
      if (candidate.entryId == entryId) {
        record = candidate;
        break;
      }
    }
    if (record == null) {
      throw KeychainManifestInvalidEntryException(
        'keychain manifest Nostr key does not exist',
      );
    }
    final materialization = record.nostrKeyMaterialization;
    if (materialization.keyKind != KeychainManifestNostrKeyKind.userGenerated ||
        !_registry.isNostrUserKeyPath(record.entry.bip85DerivationPath)) {
      throw KeychainManifestReservationMismatchException(
        'App-reserved Nostr key purposes cannot be edited',
      );
    }
    await _repository.updateNostrKeyMetadata(
      parentFingerprint: parentFingerprint,
      entryId: entryId,
      purpose: purpose ?? materialization.purpose,
      description: description == null
          ? materialization.description
          : KeychainManifestNostrKeyMaterialization.normalizeDescription(
              description,
            ),
      updatedAt: (now ?? _clock.nowUtc()).millisecondsSinceEpoch ~/ 1000,
    );
  }
}
