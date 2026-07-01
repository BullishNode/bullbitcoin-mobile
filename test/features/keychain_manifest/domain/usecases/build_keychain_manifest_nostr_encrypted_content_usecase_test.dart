import 'dart:typed_data';

import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/recoverbull_bip85.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_encryption_model.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/data/recoverbull_keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_nostr_encrypted_content_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _InMemoryKeychainManifestStore store;
  late BuildKeychainManifestNostrEncryptedContentUsecase usecase;

  setUp(() {
    store = _InMemoryKeychainManifestStore();
    usecase = BuildKeychainManifestNostrEncryptedContentUsecase(
      buildManifestFile: BuildKeychainManifestFileUsecase(repository: store),
      encryptionRepository:
          const RecoverBullKeychainManifestNostrEncryptionRepository(),
    );
  });

  test('derives a deterministic app 1642 manifest encryption key', () {
    const deriveKey = DeriveKeychainManifestNostrEncryptionKeyUsecase();

    final first = deriveKey.execute(xprvBase58: _xprv).hex;
    final second = deriveKey.execute(xprvBase58: _xprv).hex;

    expect(keychainManifestEncryptionBip85Application, 1642);
    expect(keychainManifestEncryptionBip85Path, "1642'/0'/1'");
    expect(first, second);
    expect(first, hasLength(64));
    expect(
      first,
      isNot(
        RecoverbullBip85Utils.deriveBackupKey(_xprv, "1608'/0'/586053381'"),
      ),
    );
  });

  test(
    'encrypts manifest snapshot content with recoverbull envelope',
    () async {
      await _recordInventory(store);

      final encrypted = await usecase.execute(
        parentFingerprint: 'fedcba98',
        xprvBase58: _xprv,
        now: DateTime.fromMillisecondsSinceEpoch(20000, isUtc: true),
      );

      expect(encrypted.encryptedContent, isNot(contains('fedcba98')));
      expect(encrypted.encryptedContent, isNot(contains('btc-wallet')));
      expect(encrypted.encryptedContent, isNot(contains('btcpay_wallet_seed')));
      expect(encrypted.encryptedContent, isNot(contains('manifestFile')));

      final key = const DeriveKeychainManifestNostrEncryptionKeyUsecase()
          .execute(xprvBase58: _xprv);
      final decryptedPayload = const KeychainManifestNostrEncryptionCodec()
          .decrypt(payload: encrypted.encryptedContent, key: key);
      final snapshot = const KeychainManifestNostrSnapshotCodec().decode(
        decryptedPayload,
      );

      expect(snapshot.manifestFile.parentFingerprint, 'fedcba98');
      expect(
        snapshot.manifestFile.entries.single.reservationId,
        'btcpay_wallet_seed',
      );
      expect(
        snapshot.manifestFile.entries.single.materializations.single.walletId,
        'btc-wallet',
      );
    },
  );

  test(
    'requires explicit caller decision before encrypting empty inventory',
    () async {
      await expectLater(
        usecase.execute(parentFingerprint: 'fedcba98', xprvBase58: _xprv),
        throwsA(
          isA<KeychainManifestException>().having(
            (error) => error.type,
            'type',
            KeychainManifestExceptionType.emptyInventory,
          ),
        ),
      );
    },
  );

  test('maps invalid xprv into sanitized manifest encryption error', () async {
    await _recordInventory(store);

    await expectLater(
      usecase.execute(parentFingerprint: 'fedcba98', xprvBase58: 'bad-xprv'),
      throwsA(
        isA<KeychainManifestNostrEncryptionException>()
            .having(
              (error) => error.message,
              'message',
              'failed to derive manifest encryption key',
            )
            .having(
              (error) => error.toString(),
              'string',
              isNot(contains('bad-xprv')),
            ),
      ),
    );
  });
}

Future<void> _recordInventory(_InMemoryKeychainManifestStore store) async {
  await RecordKeychainManifestEntryUsecase(repository: store).execute(
    KeychainManifestReservedDerivationRequest(
      reservationId: 'btcpay_wallet_seed',
      parentFingerprint: 'fedcba98',
      materializations: [
        KeychainManifestWalletMaterializationRequest(
          walletId: 'btc-wallet',
          childSeedFingerprint: '0123abcd',
          network: Network.bitcoinMainnet,
          walletPurpose: 'bitcoin',
          scriptType: ScriptType.bip84,
        ),
      ],
    ),
    now: DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true),
  );
}

final _xprv = Bip32Derivation.getXprvFromSeed(
  Uint8List.fromList(
    Mnemonic.fromWords(
      words: List.generate(11, (index) => 'zoo') + ['wrong'],
    ).seed,
  ),
  Network.bitcoinMainnet,
);

class _InMemoryKeychainManifestStore
    implements KeychainManifestEntryRepository {
  final entries = <KeychainManifestEntry>[];
  final records = <KeychainManifestWalletMaterializationRecord>[];

  @override
  Future<List<KeychainManifestWalletMaterializationRecord>>
  fetchWalletMaterializationRecordsByParentFingerprint(
    String parentFingerprint,
  ) async {
    return records
        .where((record) => record.entry.parentFingerprint == parentFingerprint)
        .toList(growable: false);
  }

  @override
  Future<void> insertWalletMaterializationRecords(
    List<KeychainManifestWalletMaterializationRecord> records,
  ) async {
    final nextEntries = [...entries];
    final nextRecords = [...this.records];
    for (final record in records) {
      final existingRecord = nextRecords
          .cast<KeychainManifestWalletMaterializationRecord?>()
          .firstWhere(
            (stored) => stored!.walletId == record.walletId,
            orElse: () => null,
          );
      if (existingRecord != null) {
        if (existingRecord.sameRecordAs(record)) continue;
        throw KeychainManifestEntryConflictException('duplicate');
      }
      final existingEntry = nextEntries
          .cast<KeychainManifestEntry?>()
          .firstWhere(
            (entry) => entry!.entryId == record.entry.entryId,
            orElse: () => null,
          );
      if (existingEntry == null) {
        nextEntries.add(record.entry);
      } else if (!existingEntry.sameRecordAs(record.entry)) {
        throw KeychainManifestDuplicateException('entry duplicate');
      }
      nextRecords.add(record);
    }
    entries
      ..clear()
      ..addAll(nextEntries);
    this.records
      ..clear()
      ..addAll(nextRecords);
  }
}
