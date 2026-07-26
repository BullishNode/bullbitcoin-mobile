import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
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
}

final class _EmptyManifestStore implements KeychainManifestEntryRepository {
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

final class _FixedClock implements Clock {
  final DateTime value;

  const _FixedClock(this.value);

  @override
  DateTime nowUtc() => value;
}
