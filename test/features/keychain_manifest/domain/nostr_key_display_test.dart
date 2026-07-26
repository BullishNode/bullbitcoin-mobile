import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_backup_wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/nostr_key_display.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/get_default_wallet_nostr_keys_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/get_keychain_manifest_nostr_keys_usecase.dart';
import 'package:test/test.dart';

const _parentFingerprint = '73c5da0a';
const _registry = Bip85RegistryFacade();

void main() {
  group('classification', () {
    test('maps each reserved Nostr path to its system kind', () {
      final kinds = {
        for (final path in const [
          "128002'/100'/1'",
          "128002'/101'/1'",
          "128002'/102'/1'",
        ])
          path: KeychainManifestNostrKeyDisplay.of(
            _reservedRecord(
              path: path,
              reservationId: _reservationIdForPath(path),
            ),
            registry: _registry,
          ).systemKind,
      };

      expect(kinds, {
        "128002'/100'/1'": KeychainManifestNostrSystemKind.metadataBackup,
        "128002'/101'/1'": KeychainManifestNostrSystemKind.bullnymAuth,
        "128002'/102'/1'": KeychainManifestNostrSystemKind.nip05Verification,
      });
    });

    test('marks every reserved key as a system key', () {
      final display = KeychainManifestNostrKeyDisplay.of(
        _reservedRecord(
          path: "128002'/101'/1'",
          reservationId: 'nostr_bullnym_server_auth_key',
        ),
        registry: _registry,
      );

      expect(display.isSystem, isTrue);
      expect(display.isObsolete, isFalse);
    });

    test('maps the retired wallet-metadata signing key to obsolete', () {
      final display = KeychainManifestNostrKeyDisplay.of(
        _reservedRecord(
          path:
              KeychainManifestNostrKeyDisplay.obsoleteWalletMetadataSigningPath,
          reservationId: KeychainManifestNostrKeyDisplay
              .obsoleteWalletMetadataSigningReservationId,
        ),
        registry: _registry,
      );

      expect(display.isSystem, isTrue);
      expect(
        display.systemKind,
        KeychainManifestNostrSystemKind.obsoleteWalletMetadataSigning,
      );
      expect(display.isObsolete, isTrue);
    });

    test('classifies a user key as neither system nor a role', () {
      final display = KeychainManifestNostrKeyDisplay.of(
        _userRecord(identity: 1),
        registry: _registry,
      );

      expect(display.isSystem, isFalse);
      expect(display.systemKind, KeychainManifestNostrSystemKind.none);
      expect(display.isObsolete, isFalse);
    });
  });

  group('listing filter', () {
    test('drops only the retired wallet-metadata signing record', () async {
      final repository = _MemoryRepository()
        ..nostrRecords.addAll([
          _userRecord(identity: 1),
          _reservedRecord(
            path: "128002'/100'/1'",
            reservationId: 'nostr_wallet_backup_key',
          ),
          _reservedRecord(
            path: "128002'/101'/1'",
            reservationId: 'nostr_bullnym_server_auth_key',
          ),
          _reservedRecord(
            path: "128002'/102'/1'",
            reservationId: 'nostr_nip05_public_nym_verification_key',
          ),
          _reservedRecord(
            path: KeychainManifestNostrKeyDisplay
                .obsoleteWalletMetadataSigningPath,
            reservationId: KeychainManifestNostrKeyDisplay
                .obsoleteWalletMetadataSigningReservationId,
          ),
        ]);
      final usecase = GetDefaultWalletNostrKeysUsecase(
        wallet: const _Wallet(),
        getKeys: GetKeychainManifestNostrKeysUsecase(repository: repository),
        registry: _registry,
      );

      final listed = await usecase.execute();

      expect(listed.map((record) => record.entry.bip85DerivationPath), [
        "128002'/1'/1'",
        "128002'/100'/1'",
        "128002'/101'/1'",
        "128002'/102'/1'",
      ]);
      // Read-side exclusion only: the stored row is untouched.
      expect(repository.nostrRecords, hasLength(5));
    });
  });
}

String _reservationIdForPath(String path) {
  return switch (path) {
    "128002'/100'/1'" => 'nostr_wallet_backup_key',
    "128002'/101'/1'" => 'nostr_bullnym_server_auth_key',
    "128002'/102'/1'" => 'nostr_nip05_public_nym_verification_key',
    _ => throw ArgumentError.value(path, 'path'),
  };
}

KeychainManifestNostrKeyRecord _reservedRecord({
  required String path,
  required String reservationId,
}) {
  final segments = path.split('/');
  final entry = KeychainManifestEntry(
    parentFingerprint: _parentFingerprint,
    bip85DerivationPath: path,
    reservationId: reservationId,
    entryType: 'nonWalletNostrKey',
    ownerFeature: 'nostr',
    bip85Application: int.parse(
      segments.first.substring(0, segments.first.length - 1),
    ),
    bip85Index: int.parse(segments.last.substring(0, segments.last.length - 1)),
    createdAt: 1,
    updatedAt: 1,
  );
  return KeychainManifestNostrKeyRecord(
    entry: entry,
    nostrKeyMaterialization: KeychainManifestNostrKeyMaterialization(
      entryId: entry.entryId,
      publicKeyHex: 'ab' * 32,
      keyKind: KeychainManifestNostrKeyKind.reserved,
      purpose: reservationId,
      createdAt: 1,
      updatedAt: 1,
    ),
  );
}

KeychainManifestNostrKeyRecord _userRecord({required int identity}) {
  final path = _registry.nostrUserKeyPath(identity);
  final entry = KeychainManifestEntry(
    parentFingerprint: _parentFingerprint,
    bip85DerivationPath: path,
    reservationId: _registry.nostrUserKeyReservationId,
    entryType: 'userGenerated',
    ownerFeature: 'nostr',
    bip85Application: _registry.nostrApplicationNumber,
    bip85Index: _registry.nostrUserAccount,
    createdAt: 1,
    updatedAt: 1,
  );
  return KeychainManifestNostrKeyRecord(
    entry: entry,
    nostrKeyMaterialization: KeychainManifestNostrKeyMaterialization(
      entryId: entry.entryId,
      publicKeyHex: 'cd' * 32,
      keyKind: KeychainManifestNostrKeyKind.userGenerated,
      purpose: 'key $identity',
      createdAt: 1,
      updatedAt: 1,
    ),
  );
}

final class _Wallet implements KeychainManifestBackupWalletPort {
  const _Wallet();

  @override
  Future<KeychainManifestBackupWallet> deriveDefaultWallet() async {
    return const KeychainManifestBackupWallet(
      xprvBase58: 'unused-by-the-listing-path',
      parentFingerprint: _parentFingerprint,
    );
  }
}

final class _MemoryRepository implements KeychainManifestEntryRepository {
  final nostrRecords = <KeychainManifestNostrKeyRecord>[];

  @override
  Future<List<KeychainManifestNostrKeyRecord>>
  fetchNostrKeyRecordsByParentFingerprint(String parentFingerprint) async {
    return nostrRecords
        .where((record) => record.entry.parentFingerprint == parentFingerprint)
        .toList(growable: false);
  }

  @override
  Future<List<KeychainManifestWalletMaterializationRecord>>
  fetchWalletMaterializationRecordsByParentFingerprint(
    String parentFingerprint,
  ) async => const [];

  @override
  Future<void> insertNostrKeyRecords(
    List<KeychainManifestNostrKeyRecord> records,
  ) async => nostrRecords.addAll(records);

  @override
  Future<void> insertWalletMaterializationRecords(
    List<KeychainManifestWalletMaterializationRecord> records,
  ) async {}

  @override
  Future<void> updateNostrKeyMetadata({
    required String parentFingerprint,
    required String entryId,
    required String purpose,
    required String? description,
    required int updatedAt,
  }) async {}
}
