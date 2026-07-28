import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/get_keychain_manifest_reservation_wallet_ids_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/merge_keychain_manifest_file_payloads_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_envelope.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/build_wallet_backup_envelope_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'adapts the canonical manifest payload into the unified envelope',
    () async {
      final store = _EmptyManifestStore();
      const parser = ParseKeychainManifestFileUsecase(
        codec: KeychainManifestFileCodec(),
        bip85Registry: Bip85RegistryFacade(),
      );
      final keychainManifest = KeychainManifestFacade(
        recordEntry: RecordKeychainManifestEntryUsecase(
          repository: store,
          bip85Registry: const Bip85RegistryFacade(),
        ),
        buildManifestFile: BuildKeychainManifestFileUsecase(
          repository: store,
          registry: const Bip85RegistryFacade(),
        ),
        mergeManifestFiles: const MergeKeychainManifestFilePayloadsUsecase(
          codec: KeychainManifestFileCodec(),
          parseManifest: parser,
        ),
        parseManifestFile: parser,
        reservationWalletIds: GetKeychainManifestReservationWalletIdsUsecase(
          repository: store,
        ),
      );
      final usecase = BuildWalletBackupEnvelopeUsecase(
        keychainManifest,
        _FixedClock(DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true)),
      );

      final result = await usecase.execute(
        parentFingerprint: 'FEDCBA98',
        allowEmpty: true,
      );

      expect(result, isA<Ok<WalletBackupEnvelope, WalletBackupFailure>>());
      final envelope =
          (result as Ok<WalletBackupEnvelope, WalletBackupFailure>).value;
      expect(envelope.parentFingerprint, 'fedcba98');
      expect(envelope.createdAt, 2);
      expect(
        envelope.manifest.payload,
        '{"version":1,"parentFingerprint":"fedcba98","generatedAt":2,'
        '"inventoryUpdatedAt":0,"entryCount":0,"materializationCount":0,'
        '"entries":[]}',
      );
    },
  );

  test('includes user-created Nostr keys without private material', () async {
    final store = _EmptyManifestStore();
    final entry = KeychainManifestEntry(
      parentFingerprint: 'fedcba98',
      bip85DerivationPath: "128002'/1'/1'",
      reservationId: 'nostr_user_key',
      entryType: 'userGenerated',
      ownerFeature: 'nostr',
      bip85Application: 128002,
      bip85Index: 1,
      createdAt: 1,
      updatedAt: 1,
    );
    store.nostrRecords.add(
      KeychainManifestNostrKeyRecord(
        entry: entry,
        nostrKeyMaterialization: KeychainManifestNostrKeyMaterialization(
          entryId: entry.entryId,
          publicKeyHex: 'ab' * 32,
          keyKind: KeychainManifestNostrKeyKind.userGenerated,
          purpose: 'personal identity',
          createdAt: 1,
          updatedAt: 1,
        ),
      ),
    );
    const parser = ParseKeychainManifestFileUsecase(
      codec: KeychainManifestFileCodec(),
      bip85Registry: Bip85RegistryFacade(),
    );
    final keychainManifest = KeychainManifestFacade(
      recordEntry: RecordKeychainManifestEntryUsecase(
        repository: store,
        bip85Registry: const Bip85RegistryFacade(),
      ),
      buildManifestFile: BuildKeychainManifestFileUsecase(
        repository: store,
        registry: const Bip85RegistryFacade(),
      ),
      mergeManifestFiles: const MergeKeychainManifestFilePayloadsUsecase(
        codec: KeychainManifestFileCodec(),
        parseManifest: parser,
      ),
      parseManifestFile: parser,
      reservationWalletIds: GetKeychainManifestReservationWalletIdsUsecase(
        repository: store,
      ),
    );
    final usecase = BuildWalletBackupEnvelopeUsecase(
      keychainManifest,
      _FixedClock(DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true)),
    );

    final result = await usecase.execute(parentFingerprint: 'fedcba98');

    expect(result, isA<Ok<WalletBackupEnvelope, WalletBackupFailure>>());
    final envelope =
        (result as Ok<WalletBackupEnvelope, WalletBackupFailure>).value;
    final manifest = const KeychainManifestFileCodec().decode(
      envelope.manifest.payload,
    );
    final nostr =
        manifest.entries.single.materializations.single
            as KeychainManifestFileNostrKeyMaterialization;
    expect(manifest.entries.single.bip85DerivationPath, "128002'/1'/1'");
    expect(nostr.publicKeyHex, 'ab' * 32);
    expect(nostr.keyKind, KeychainManifestNostrKeyKind.userGenerated.name);
    expect(nostr.purpose, 'personal identity');
    expect(envelope.manifest.payload, isNot(contains('nsec')));
    expect(envelope.manifest.payload, isNot(contains('private')));
  });
}

final class _EmptyManifestStore implements KeychainManifestEntryRepository {
  final nostrRecords = <KeychainManifestNostrKeyRecord>[];

  @override
  Future<List<KeychainManifestNostrKeyRecord>>
  fetchNostrKeyRecordsByParentFingerprint(String parentFingerprint) async =>
      nostrRecords
          .where(
            (record) =>
                record.entry.parentFingerprint ==
                parentFingerprint.toLowerCase(),
          )
          .toList(growable: false);

  @override
  Future<List<KeychainManifestWalletMaterializationRecord>>
  fetchWalletMaterializationRecordsByParentFingerprint(
    String parentFingerprint,
  ) async => const [];

  @override
  Future<void> insertWalletMaterializationRecords(
    List<KeychainManifestWalletMaterializationRecord> records,
  ) async {}

  @override
  Future<void> insertNostrKeyRecords(
    List<KeychainManifestNostrKeyRecord> records,
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

final class _FixedClock implements Clock {
  final DateTime value;

  const _FixedClock(this.value);

  @override
  DateTime nowUtc() => value;
}
