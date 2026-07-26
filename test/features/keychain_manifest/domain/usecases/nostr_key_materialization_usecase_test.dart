import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_backup_wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/create_keychain_manifest_nostr_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_nostr_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/reveal_keychain_manifest_nostr_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/update_keychain_manifest_nostr_key_purpose_usecase.dart';
import 'package:test/test.dart';

const _xprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
const _parentFingerprint = '73c5da0a';
const _registry = Bip85RegistryFacade();

void main() {
  test(
    'allocates after the user identity high-water mark without filling gaps',
    () async {
      final repository = _MemoryRepository()
        ..nostrRecords.add(_record(identity: 2));
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

      expect(created.derivationPath, "128002'/3'/1'");
      expect(created.purpose, 'personal identity');
      expect(repository.nostrRecords.last.entry.bip85Index, 1);
      expect(
        repository.nostrRecords.last.entry.bip85DerivationPath,
        isNot(contains("/100'")),
      );
    },
  );

  test('jumps over the complete app-reserved identity range', () async {
    final repository = _MemoryRepository()
      ..nostrRecords.add(_record(identity: 99));
    final create = CreateKeychainManifestNostrKeyUsecase(
      wallet: const _Wallet(),
      repository: repository,
      record: RecordKeychainManifestNostrKeyUsecase(
        repository: repository,
        registry: _registry,
      ),
      registry: _registry,
    );

    final created = await create.execute(purpose: 'after app range');

    expect(created.derivationPath, "128002'/200'/1'");
    expect(repository.nostrRecords, hasLength(2));
  });

  test(
    'retries from the durable high-water mark after an allocation race',
    () async {
      final repository = _RacingRepository();
      final create = CreateKeychainManifestNostrKeyUsecase(
        wallet: const _Wallet(),
        repository: repository,
        record: RecordKeychainManifestNostrKeyUsecase(
          repository: repository,
          registry: _registry,
        ),
        registry: _registry,
      );

      final created = await create.execute(purpose: 'second caller');

      expect(created.derivationPath, "128002'/2'/1'");
      expect(
        repository.nostrRecords.map(
          (record) => record.entry.bip85DerivationPath,
        ),
        ["128002'/1'/1'", "128002'/2'/1'"],
      );
    },
  );

  test(
    'does not overwrite a concurrent allocator purpose before retrying',
    () async {
      final repository = _ObservedAllocationRaceRepository();
      final create = CreateKeychainManifestNostrKeyUsecase(
        wallet: const _Wallet(),
        repository: repository,
        record: RecordKeychainManifestNostrKeyUsecase(
          repository: repository,
          registry: _registry,
        ),
        registry: _registry,
      );

      final created = await create.execute(
        purpose: 'second caller',
        now: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      );

      expect(created.derivationPath, "128002'/2'/1'");
      expect(repository.nostrRecords, hasLength(2));
      expect(
        repository.nostrRecords.first.nostrKeyMaterialization.purpose,
        'first caller',
      );
      expect(
        repository.nostrRecords.last.nostrKeyMaterialization.purpose,
        'second caller',
      );
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
    'recovery preserves a newer revision when the purpose is unchanged',
    () async {
      final repository = _MemoryRepository();
      final usecase = RecordKeychainManifestNostrKeyUsecase(
        repository: repository,
        registry: _registry,
      );
      final request = _request(purpose: 'same purpose');

      await usecase.execute(
        request,
        now: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
      expect(
        await usecase.execute(
          request,
          now: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(4000, isUtc: true),
        ),
        isTrue,
      );
      expect(
        repository.nostrRecords.single.nostrKeyMaterialization.updatedAt,
        4,
      );
    },
  );

  test('does not export an app-reserved Nostr service key', () async {
    final record = _reservedRecord();

    await expectLater(
      const RevealKeychainManifestNostrKeyUsecase(
        wallet: _Wallet(),
      ).execute(record),
      throwsStateError,
    );
  });

  test('does not edit an app-reserved Nostr key purpose', () async {
    final repository = _MemoryRepository()..nostrRecords.add(_reservedRecord());
    final record = repository.nostrRecords.single;
    final usecase = UpdateKeychainManifestNostrKeyPurposeUsecase(
      repository: repository,
      registry: _registry,
    );

    await expectLater(
      usecase.execute(
        parentFingerprint: record.entry.parentFingerprint,
        entryId: record.entryId,
        purpose: 'renamed service key',
      ),
      throwsA(isA<KeychainManifestReservationMismatchException>()),
    );
    // The guard covers every editable field, not just the purpose: a
    // description-only edit must be refused the same way.
    await expectLater(
      usecase.execute(
        parentFingerprint: record.entry.parentFingerprint,
        entryId: record.entryId,
        description: 'annotated service key',
      ),
      throwsA(isA<KeychainManifestReservationMismatchException>()),
    );
    expect(
      repository.nostrRecords.single.nostrKeyMaterialization.purpose,
      'Wallet backup',
    );
    expect(
      repository.nostrRecords.single.nostrKeyMaterialization.description,
      isNull,
    );
  });

  test('creates a user key with a description', () async {
    final repository = _MemoryRepository();
    final create = CreateKeychainManifestNostrKeyUsecase(
      wallet: const _Wallet(),
      repository: repository,
      record: RecordKeychainManifestNostrKeyUsecase(
        repository: repository,
        registry: _registry,
      ),
      registry: _registry,
    );

    final created = await create.execute(
      purpose: 'personal identity',
      description: '  long-form notes and replies  ',
    );

    expect(created.description, 'long-form notes and replies');
    expect(
      repository.nostrRecords.single.nostrKeyMaterialization.description,
      'long-form notes and replies',
    );
  });

  test('creates a user key without a description', () async {
    final repository = _MemoryRepository();
    final create = CreateKeychainManifestNostrKeyUsecase(
      wallet: const _Wallet(),
      repository: repository,
      record: RecordKeychainManifestNostrKeyUsecase(
        repository: repository,
        registry: _registry,
      ),
      registry: _registry,
    );

    final created = await create.execute(purpose: 'personal identity');

    expect(created.description, isNull);
    expect(
      repository.nostrRecords.single.nostrKeyMaterialization.description,
      isNull,
    );
  });

  test('records app-reserved keys without a description', () async {
    final repository = _MemoryRepository();
    final usecase = RecordKeychainManifestNostrKeyUsecase(
      repository: repository,
      registry: _registry,
    );

    await usecase.execute(
      KeychainManifestNostrKeyRequest(
        reservationId: 'nostr_wallet_backup_key',
        parentFingerprint: _parentFingerprint,
        derivationPath: "128002'/100'/1'",
        publicKeyHex: 'ab' * 32,
        keyKind: KeychainManifestNostrKeyKind.reserved,
        purpose: 'Nostr Wallet Backup',
      ),
    );

    expect(
      repository.nostrRecords.single.nostrKeyMaterialization.description,
      isNull,
    );
  });

  test('edits a user key purpose without touching its description', () async {
    final repository = _MemoryRepository()
      ..nostrRecords.add(_record(identity: 1, description: 'kept'));
    final record = repository.nostrRecords.single;

    await UpdateKeychainManifestNostrKeyPurposeUsecase(
      repository: repository,
      registry: _registry,
    ).execute(
      parentFingerprint: record.entry.parentFingerprint,
      entryId: record.entryId,
      purpose: 'renamed user key',
      now: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );

    final updated = repository.nostrRecords.single.nostrKeyMaterialization;
    expect(updated.purpose, 'renamed user key');
    expect(updated.description, 'kept');
  });

  test('edits a user key description without touching its purpose', () async {
    final repository = _MemoryRepository()
      ..nostrRecords.add(_record(identity: 1, purpose: 'kept purpose'));
    final record = repository.nostrRecords.single;

    await UpdateKeychainManifestNostrKeyPurposeUsecase(
      repository: repository,
      registry: _registry,
    ).execute(
      parentFingerprint: record.entry.parentFingerprint,
      entryId: record.entryId,
      description: 'added later',
      now: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );

    final updated = repository.nostrRecords.single.nostrKeyMaterialization;
    expect(updated.purpose, 'kept purpose');
    expect(updated.description, 'added later');
  });

  test('edits a user key purpose and description in one revision', () async {
    final repository = _MemoryRepository()
      ..nostrRecords.add(_record(identity: 1, description: 'old note'));
    final record = repository.nostrRecords.single;

    await UpdateKeychainManifestNostrKeyPurposeUsecase(
      repository: repository,
      registry: _registry,
    ).execute(
      parentFingerprint: record.entry.parentFingerprint,
      entryId: record.entryId,
      purpose: 'renamed user key',
      description: 'new note',
      now: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );

    final updated = repository.nostrRecords.single.nostrKeyMaterialization;
    expect(updated.purpose, 'renamed user key');
    expect(updated.description, 'new note');
    expect(updated.updatedAt, 2);
  });

  test('clears a user key description with an empty value', () async {
    final repository = _MemoryRepository()
      ..nostrRecords.add(_record(identity: 1, description: 'to be cleared'));
    final record = repository.nostrRecords.single;

    await UpdateKeychainManifestNostrKeyPurposeUsecase(
      repository: repository,
      registry: _registry,
    ).execute(
      parentFingerprint: record.entry.parentFingerprint,
      entryId: record.entryId,
      description: '   ',
      now: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );

    expect(
      repository.nostrRecords.single.nostrKeyMaterialization.description,
      isNull,
    );
  });

  test('edits a purpose only inside the user Nostr namespace', () async {
    final repository = _MemoryRepository()
      ..nostrRecords.add(_record(identity: 1));
    final record = repository.nostrRecords.single;

    await UpdateKeychainManifestNostrKeyPurposeUsecase(
      repository: repository,
      registry: _registry,
    ).execute(
      parentFingerprint: record.entry.parentFingerprint,
      entryId: record.entryId,
      purpose: 'renamed user key',
      now: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );

    expect(
      repository.nostrRecords.single.nostrKeyMaterialization.purpose,
      'renamed user key',
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

KeychainManifestNostrKeyRecord _record({
  required int identity,
  String? purpose,
  String? publicKeyHex,
  String? description,
}) {
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
      publicKeyHex: publicKeyHex ?? 'ab' * 32,
      keyKind: KeychainManifestNostrKeyKind.userGenerated,
      purpose: purpose ?? 'key $identity',
      description: description,
      createdAt: 1,
      updatedAt: 1,
    ),
  );
}

KeychainManifestNostrKeyRecord _reservedRecord() {
  final entry = KeychainManifestEntry(
    parentFingerprint: _parentFingerprint,
    bip85DerivationPath: "128002'/100'/1'",
    reservationId: 'nostr_wallet_backup_key',
    entryType: 'nonWalletNostrKey',
    ownerFeature: 'nostr',
    bip85Application: 128002,
    bip85Index: 1,
    createdAt: 1,
    updatedAt: 1,
  );
  return KeychainManifestNostrKeyRecord(
    entry: entry,
    nostrKeyMaterialization: KeychainManifestNostrKeyMaterialization(
      entryId: entry.entryId,
      publicKeyHex: 'ab' * 32,
      keyKind: KeychainManifestNostrKeyKind.reserved,
      purpose: 'Wallet backup',
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
  Future<void> updateNostrKeyMetadata({
    required String parentFingerprint,
    required String entryId,
    required String purpose,
    required String? description,
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
        description: description,
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

final class _RacingRepository extends _MemoryRepository {
  var _collideOnce = true;

  @override
  Future<void> insertNostrKeyRecords(
    List<KeychainManifestNostrKeyRecord> records,
  ) async {
    if (_collideOnce) {
      _collideOnce = false;
      nostrRecords.add(records.single);
      throw KeychainManifestDuplicateException('simulated allocation race');
    }
    await super.insertNostrKeyRecords(records);
  }
}

final class _ObservedAllocationRaceRepository extends _MemoryRepository {
  var _fetchCount = 0;

  @override
  Future<List<KeychainManifestNostrKeyRecord>>
  fetchNostrKeyRecordsByParentFingerprint(String parentFingerprint) async {
    _fetchCount += 1;
    if (_fetchCount == 2) {
      final path = _registry.nostrUserKeyPath(1);
      nostrRecords.add(
        _record(
          identity: 1,
          purpose: 'first caller',
          publicKeyHex: NostrKeychainHandle.deriveFromBip85Path(
            xprvBase58: _xprv,
            hardenedPath: path,
          ).publicKeyHex,
        ),
      );
    }
    return super.fetchNostrKeyRecordsByParentFingerprint(parentFingerprint);
  }
}
