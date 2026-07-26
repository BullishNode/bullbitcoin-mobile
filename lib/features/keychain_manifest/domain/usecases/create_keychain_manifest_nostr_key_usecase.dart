// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_backup_wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_nostr_key_usecase.dart';

final class CreatedKeychainManifestNostrKey {
  final String parentFingerprint;
  final String derivationPath;
  final String publicKeyHex;
  final String purpose;

  const CreatedKeychainManifestNostrKey({
    required this.parentFingerprint,
    required this.derivationPath,
    required this.publicKeyHex,
    required this.purpose,
  });
}

final class CreateKeychainManifestNostrKeyUsecase {
  final KeychainManifestBackupWalletPort _wallet;
  final KeychainManifestEntryRepository _repository;
  final RecordKeychainManifestNostrKeyUsecase _record;
  final Bip85RegistryFacade _registry;
  final Clock _clock;

  const CreateKeychainManifestNostrKeyUsecase({
    required KeychainManifestBackupWalletPort wallet,
    required KeychainManifestEntryRepository repository,
    required RecordKeychainManifestNostrKeyUsecase record,
    required Bip85RegistryFacade registry,
    this._clock = const SystemClock(),
  }) : _wallet = wallet,
       _repository = repository,
       _record = record,
       _registry = registry;

  Future<CreatedKeychainManifestNostrKey> execute({
    required String purpose,
    DateTime? now,
  }) async {
    final source = await _wallet.deriveDefaultWallet();
    final timestamp = now ?? _clock.nowUtc();
    while (true) {
      final existing = await _repository
          .fetchNostrKeyRecordsByParentFingerprint(source.parentFingerprint);
      var highWaterIdentity = 0;
      for (final record in existing.where(
        (record) =>
            record.nostrKeyMaterialization.keyKind ==
            KeychainManifestNostrKeyKind.userGenerated,
      )) {
        final identity = _registry.nostrUserKeyIdentity(
          record.entry.bip85DerivationPath,
        );
        if (identity == null ||
            record.entry.reservationId != _registry.nostrUserKeyReservationId) {
          throw StateError('Recorded user Nostr key has an invalid path');
        }
        if (identity > highWaterIdentity) highWaterIdentity = identity;
      }

      var identity = highWaterIdentity + 1;
      if (_registry.isNostrAppReservedIdentity(identity)) {
        identity = _registry.nostrAppReservedIdentityEnd + 1;
      }
      if (identity > _registry.nostrUserIdentityEnd) {
        throw StateError('No user Nostr identity slots remain');
      }
      final path = _registry.nostrUserKeyPath(identity);
      final publicKeyHex = NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: source.xprvBase58,
        hardenedPath: path,
      ).publicKeyHex;
      try {
        final changed = await _record.execute(
          KeychainManifestNostrKeyRequest(
            reservationId: _registry.nostrUserKeyReservationId,
            parentFingerprint: source.parentFingerprint,
            derivationPath: path,
            publicKeyHex: publicKeyHex,
            keyKind: KeychainManifestNostrKeyKind.userGenerated,
            purpose: purpose,
          ),
          now: timestamp,
        );
        if (!changed) continue;
        return CreatedKeychainManifestNostrKey(
          parentFingerprint: source.parentFingerprint,
          derivationPath: path,
          publicKeyHex: publicKeyHex,
          purpose: purpose.trim(),
        );
      } on KeychainManifestEntryConflictException {
        // Another allocator committed this path after our high-water read.
      } on KeychainManifestDuplicateException {
        // Refetch the durable high-water mark and allocate the next identity.
      }
    }
  }
}
