// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';

class RecordKeychainManifestNostrKeyUsecase {
  final KeychainManifestEntryRepository _repository;
  final Bip85RegistryFacade _registry;
  final Clock _clock;

  RecordKeychainManifestNostrKeyUsecase({
    required KeychainManifestEntryRepository repository,
    required Bip85RegistryFacade registry,
    Clock clock = const SystemClock(),
  }) : _repository = repository,
       _registry = registry,
       _clock = clock;

  Future<bool> execute(
    KeychainManifestNostrKeyRequest request, {
    DateTime? now,
    DateTime? updatedAt,
  }) async {
    final path = KeychainManifestBip85Path.normalize(request.derivationPath);
    final effectiveNow = now ?? _clock.nowUtc();
    final timestamp = effectiveNow.millisecondsSinceEpoch ~/ 1000;
    final updatedTimestamp =
        (updatedAt ?? effectiveNow).millisecondsSinceEpoch ~/ 1000;
    final reservation = _registry.reservationById(request.reservationId);
    final isUserKey =
        request.reservationId == _registry.nostrUserKeyReservationId;

    final String entryType;
    final String ownerFeature;
    final int application;
    if (isUserKey) {
      if (request.keyKind != KeychainManifestNostrKeyKind.userGenerated ||
          !_registry.isNostrUserKeyPath(path)) {
        throw KeychainManifestReservationMismatchException(
          'user Nostr key does not match the reserved user namespace',
        );
      }
      entryType = 'userGenerated';
      ownerFeature = 'nostr';
      application = _registry.nostrUserKeyApplication;
    } else {
      if (request.keyKind != KeychainManifestNostrKeyKind.reserved ||
          reservation is! Bip85KeyReservation ||
          !reservation.scope.matchesExactPath(path) ||
          reservation.application.number != _registry.nostrApplicationNumber) {
        throw KeychainManifestReservationMismatchException(
          'reserved Nostr key does not match its registry reservation',
        );
      }
      entryType = reservation.purpose.name;
      ownerFeature = reservation.owner.name;
      application = reservation.application.number;
    }

    final index = _lastPathSegment(path);
    final entry = KeychainManifestEntry(
      parentFingerprint: request.parentFingerprint,
      bip85DerivationPath: path,
      reservationId: request.reservationId,
      entryType: entryType,
      ownerFeature: ownerFeature,
      bip85Application: application,
      bip85Index: index,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final materialization = KeychainManifestNostrKeyMaterialization(
      entryId: entry.entryId,
      publicKeyHex: request.publicKeyHex,
      keyKind: request.keyKind,
      purpose: request.purpose,
      createdAt: timestamp,
      updatedAt: updatedTimestamp,
    );
    final existing = await _repository.fetchNostrKeyRecordsByParentFingerprint(
      entry.parentFingerprint,
    );
    final existingAtPath = existing.where(
      (record) => record.entry.bip85DerivationPath == path,
    );
    if (existingAtPath.isNotEmpty) {
      final stored = existingAtPath.single;
      if (stored.nostrKeyMaterialization.publicKeyHex ==
              materialization.publicKeyHex &&
          stored.nostrKeyMaterialization.keyKind == materialization.keyKind) {
        final storedMaterialization = stored.nostrKeyMaterialization;
        if (storedMaterialization.purpose == materialization.purpose ||
            materialization.updatedAt < storedMaterialization.updatedAt) {
          return false;
        }
        if (materialization.updatedAt == storedMaterialization.updatedAt) {
          throw KeychainManifestEntryConflictException(
            'Nostr key purpose conflicts at the same revision',
          );
        }
        await _repository.updateNostrKeyPurpose(
          parentFingerprint: entry.parentFingerprint,
          entryId: entry.entryId,
          purpose: materialization.purpose,
          updatedAt: materialization.updatedAt,
        );
        return true;
      }
      throw KeychainManifestEntryConflictException(
        'Nostr key path already contains different key material',
      );
    }
    await _repository.insertNostrKeyRecords([
      KeychainManifestNostrKeyRecord(
        entry: entry,
        nostrKeyMaterialization: materialization,
      ),
    ]);
    return true;
  }

  int _lastPathSegment(String path) {
    final segment = path.split('/').last;
    final value = int.tryParse(segment.substring(0, segment.length - 1));
    if (value == null) {
      throw KeychainManifestInvalidEntryException(
        'Nostr key path has an invalid final segment',
      );
    }
    return value;
  }
}
