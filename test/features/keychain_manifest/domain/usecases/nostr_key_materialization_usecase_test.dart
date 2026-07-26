import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_backup_wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/create_keychain_manifest_nostr_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_nostr_key_usecase.dart';
import 'package:test/test.dart';

const _xprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
const _parentFingerprint = '73c5da0a';
const _registry = Bip85RegistryFacade();

void main() {
  test(
    'allocates the first free user identity and never the app range',
    () async {
      final repository = _MemoryRepository()
        ..nostrRecords.add(_record(identity: 1));
      final record = RecordKeychainManifestNostrKeyUsecase(
        repository: repository,
        registry: _registry,
      );
      final create = CreateKeychainManifestNostrKeyUsecase(
        wallet: const _Wallet(),
        repository: repository,
        record: record,
        registry: _registry,
      );

      final created = await create.execute(
        purpose: '  personal identity  ',
        now: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      );

      expect(created.derivationPath, "128002'/2'/1'");
      expect(created.purpose, 'personal identity');
      expect(repository.nostrRecords.last.entry.bip85Index, 1);
      expect(
        repository.nostrRecords.last.entry.bip85DerivationPath,
        isNot(contains("/100'")),
      );
    },
  );

  test(
    'fails instead of crossing into the app namespace when slots are full',
    () async {
      final repository = _MemoryRepository();
      for (var identity = 1; identity <= 99; identity++) {
        repository.nostrRecords.add(_record(identity: identity));
      }
      final create = CreateKeychainManifestNostrKeyUsecase(
        wallet: const _Wallet(),
        repository: repository,
        record: RecordKeychainManifestNostrKeyUsecase(
          repository: repository,
          registry: _registry,
        ),
        registry: _registry,
      );

      await expectLater(
        create.execute(purpose: 'one too many'),
        throwsA(isA<StateError>()),
      );
      expect(repository.nostrRecords, hasLength(99));
    },
  );

  test('recovery applies only a newer purpose revision', () async {
    final repository = _MemoryRepository();
    final usecase = RecordKeychainManifestNostrKeyUsecase(
      repository: repository,
      registry: _registry,
    );
    final request = _request(purpose: 'old purpose');

    expect(
      await usecase.execute(
        request,
        now: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      ),
      isTrue,
    );
    expect(
      await usecase.execute(
        _request(purpose: 'new purpose'),
        now: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(3000, isUtc: true),
      ),
      isTrue,
    );
    expect(
      repository.nostrRecords.single.nostrKeyMaterialization.purpose,
      'new purpose',
    );
    expect(repository.nostrRecords.single.nostrKeyMaterialization.updatedAt, 3);

    expect(
      await usecase.execute(
        request,
        now: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      ),
      isFalse,
    );
    expect(
      repository.nostrRecords.single.nostrKeyMaterialization.purpose,
      'new purpose',
    );
  });

  test(
    'repeated materialization of the same reserved key is not a change',
    () async {
      final repository = _MemoryRepository();
      final usecase = RecordKeychainManifestNostrKeyUsecase(
        repository: repository,
        registry: _registry,
      );
      final request = _request(purpose: 'personal identity');

      expect(await usecase.execute(request), isTrue);
      expect(await usecase.execute(request), isFalse);
      expect(repository.nostrRecords, hasLength(1));
    },
  );
}

KeychainManifestNostrKeyRequest _request({required String purpose}) {
  return KeychainManifestNostrKeyRequest(
    reservationId: _registry.nostrUserKeyReservationId,
    parentFingerprint: _parentFingerprint,
    derivationPath: "128002'/1'/1'",
    publicKeyHex: 'ab' * 32,
    keyKind: KeychainManifestNostrKeyKind.userGenerated,
    purpose: purpose,
  );
}

KeychainManifestNostrKeyRecord _record({required int identity}) {
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
      publicKeyHex: 'ab' * 32,
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
      xprvBase58: _xprv,
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
  Future<void> insertNostrKeyRecords(
    List<KeychainManifestNostrKeyRecord> records,
  ) async {
    nostrRecords.addAll(records);
  }

  @override
  Future<void> updateNostrKeyPurpose({
    required String parentFingerprint,
    required String entryId,
    required String purpose,
    required int updatedAt,
  }) async {
    final index = nostrRecords.indexWhere(
      (record) =>
          record.entry.parentFingerprint == parentFingerprint &&
          record.entryId == entryId,
    );
    final stored = nostrRecords[index];
    final materialization = stored.nostrKeyMaterialization;
    nostrRecords[index] = KeychainManifestNostrKeyRecord(
      entry: stored.entry,
      nostrKeyMaterialization: KeychainManifestNostrKeyMaterialization(
        entryId: materialization.entryId,
        publicKeyHex: materialization.publicKeyHex,
        keyKind: materialization.keyKind,
        purpose: purpose,
        createdAt: materialization.createdAt,
        updatedAt: updatedAt,
      ),
    );
  }

  @override
  Future<List<KeychainManifestWalletMaterializationRecord>>
  fetchWalletMaterializationRecordsByParentFingerprint(
    String parentFingerprint,
  ) async => const [];

  @override
  Future<void> insertWalletMaterializationRecords(
    List<KeychainManifestWalletMaterializationRecord> records,
  ) async {}
}
