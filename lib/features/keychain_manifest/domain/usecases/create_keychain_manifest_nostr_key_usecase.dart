// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_backup_wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
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
    final existing = await _repository.fetchNostrKeyRecordsByParentFingerprint(
      source.parentFingerprint,
    );
    final usedPaths = existing
        .map((record) => record.entry.bip85DerivationPath)
        .toSet();
    String? path;
    for (
      var identity = _registry.nostrUserIdentityStart;
      identity <= _registry.nostrUserIdentityEnd;
      identity++
    ) {
      final candidate = _registry.nostrUserKeyPath(identity);
      if (!usedPaths.contains(candidate)) {
        path = candidate;
        break;
      }
    }
    if (path == null) {
      throw StateError('No user Nostr identity slots remain');
    }

    final publicKeyHex = NostrKeychainHandle.deriveFromBip85Path(
      xprvBase58: source.xprvBase58,
      hardenedPath: path,
    ).publicKeyHex;
    final timestamp = now ?? _clock.nowUtc();
    await _record.execute(
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
    return CreatedKeychainManifestNostrKey(
      parentFingerprint: source.parentFingerprint,
      derivationPath: path,
      publicKeyHex: publicKeyHex,
      purpose: purpose.trim(),
    );
  }
}
