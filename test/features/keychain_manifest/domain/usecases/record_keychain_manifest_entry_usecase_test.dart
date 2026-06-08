import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_entry_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_request.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/record_keychain_manifest_entry_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _InMemoryKeychainManifestStore store;
  late RecordKeychainManifestEntryUsecase usecase;

  setUp(() {
    store = _InMemoryKeychainManifestStore();
    usecase = RecordKeychainManifestEntryUsecase(repository: store);
  });

  test('normalizes fingerprints and registry-relative BIP85 paths', () {
    final record = _record(
      parentFingerprint: ' FEDCBA98 ',
      childSeedFingerprint: ' 0123ABCD ',
      bip85DerivationPath: "39'/0'/12'/00100'",
    );

    expect(record.entry.parentFingerprint, 'fedcba98');
    expect(record.walletMaterialization.childSeedFingerprint, '0123abcd');
    expect(record.entry.bip85DerivationPath, "39'/0'/12'/100'");
  });

  test('rejects invalid fingerprints and malformed BIP85 paths', () {
    expect(
      () => _record(parentFingerprint: 'not-hex'),
      throwsA(isA<KeychainManifestInvalidEntryException>()),
    );
    expect(
      () => _record(bip85DerivationPath: "39/0'/12'/100'"),
      throwsA(isA<KeychainManifestInvalidEntryException>()),
    );
  });

  test('rejects explicit entry ids that do not match entry identity', () {
    expect(
      () => _record(entryId: "fedcba98:39'/0'/12'/101'"),
      throwsA(isA<KeychainManifestInvalidEntryException>()),
    );
  });

  test(
    'records reserved derivation commands with registry-owned metadata',
    () async {
      await usecase.execute(
        const KeychainManifestReservedDerivationRequest(
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
        now: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );

      expect(store.entries.single.reservationId, 'btcpay_wallet_seed');
      expect(store.entries.single.entryType, 'walletSeed');
      expect(store.entries.single.ownerFeature, 'btcpay');
      expect(store.entries.single.bip85DerivationPath, "39'/0'/12'/100'");
      expect(store.entries.single.bip85Index, 100);
    },
  );

  test('records exact duplicates idempotently', () async {
    await usecase.execute(_command());
    await usecase.execute(_command());

    expect(store.records, hasLength(1));
  });

  test(
    'rejects the same wallet id with a different wallet materialization',
    () async {
      await usecase.execute(_command());

      expect(
        () => usecase.execute(_command(network: Network.liquidMainnet)),
        throwsA(isA<KeychainManifestEntryConflictException>()),
      );
    },
  );

  test('allows the same BIP85 entry and network for another wallet', () async {
    await usecase.execute(_command());

    expect(
      () => usecase.execute(_command(walletId: 'other-wallet')),
      returnsNormally,
    );
  });

  test('allows the same BIP85 entry on a different wallet network', () async {
    await usecase.execute(_command());
    await usecase.execute(
      _command(walletId: 'lbtc-wallet', network: Network.liquidMainnet),
    );

    expect(store.entries, hasLength(1));
    expect(store.records, hasLength(2));
  });

  test('rejects entries that do not match the reservation', () async {
    expect(
      () => usecase.execute(_command(reservationId: 'unknown')),
      throwsA(isA<KeychainManifestReservationMismatchException>()),
    );
  });

  test('records Lightning Address reserved wallet metadata', () async {
    await usecase.execute(
      _command(
        reservationId: 'lightning_address_wallet_seed',
        walletId: 'lightning-address-wallet',
        network: Network.liquidMainnet,
        walletPurpose: 'liquid',
      ),
    );

    expect(store.entries.single.reservationId, 'lightning_address_wallet_seed');
    expect(store.entries.single.ownerFeature, 'lightningAddress');
    expect(store.entries.single.bip85DerivationPath, "39'/0'/12'/101'");
  });

  test('rejects Payment Page wallet metadata until it is manifest-enabled', () {
    expect(
      () => usecase.execute(
        _command(
          reservationId: 'payment_page_wallet_seed',
          walletId: 'payment-page-wallet',
          network: Network.liquidMainnet,
          walletPurpose: 'liquid',
        ),
      ),
      throwsA(isA<KeychainManifestEntryConflictException>()),
    );
  });

  test('does not keep batch records if a later record fails', () async {
    store.failOnWalletId = 'lbtc-wallet';

    await expectLater(
      usecase.execute(
        _command(
          extraWalletMaterializations: [
            const KeychainManifestWalletMaterializationRequest(
              walletId: 'lbtc-wallet',
              childSeedFingerprint: '0123abcd',
              network: Network.liquidMainnet,
              walletPurpose: 'liquid',
              scriptType: ScriptType.bip84,
            ),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(store.records, isEmpty);
    expect(store.entries, isEmpty);

    store.failOnWalletId = null;
    await usecase.execute(
      _command(
        extraWalletMaterializations: [
          const KeychainManifestWalletMaterializationRequest(
            walletId: 'lbtc-wallet',
            childSeedFingerprint: '0123abcd',
            network: Network.liquidMainnet,
            walletPurpose: 'liquid',
            scriptType: ScriptType.bip84,
          ),
        ],
      ),
    );

    expect(store.records.map((record) => record.walletId), [
      'btc-wallet',
      'lbtc-wallet',
    ]);
    expect(store.entries, hasLength(1));
  });

  test(
    'treats duplicate identical rows after precheck as idempotent',
    () async {
      store.insertIdenticalRowsBeforeBatch = true;

      await usecase.execute(_command());

      expect(store.records.map((record) => record.walletId), ['btc-wallet']);
      expect(store.entries, hasLength(1));
    },
  );
}

KeychainManifestReservedDerivationRequest _command({
  String reservationId = 'btcpay_wallet_seed',
  String parentFingerprint = 'fedcba98',
  String walletId = 'btc-wallet',
  String childSeedFingerprint = '0123abcd',
  Network network = Network.bitcoinMainnet,
  String walletPurpose = 'bitcoin',
  ScriptType scriptType = ScriptType.bip84,
  List<KeychainManifestWalletMaterializationRequest>
      extraWalletMaterializations =
      const [],
}) {
  return KeychainManifestReservedDerivationRequest(
    reservationId: reservationId,
    parentFingerprint: parentFingerprint,
    materializations: [
      KeychainManifestWalletMaterializationRequest(
        walletId: walletId,
        childSeedFingerprint: childSeedFingerprint,
        network: network,
        walletPurpose: walletPurpose,
        scriptType: scriptType,
      ),
      ...extraWalletMaterializations,
    ],
  );
}

KeychainManifestWalletMaterializationRecord _record({
  String? entryId,
  String walletId = 'btc-wallet',
  String parentFingerprint = 'fedcba98',
  String childSeedFingerprint = '0123abcd',
  String bip85DerivationPath = "39'/0'/12'/100'",
  String network = 'bitcoinMainnet',
  String reservationId = 'btcpay_wallet_seed',
  String entryType = 'walletSeed',
  String ownerFeature = 'btcpay',
  int bip85Application = 39,
  int bip85Index = 100,
  String walletPurpose = 'bitcoin',
  String scriptType = 'bip84',
}) {
  final entry = KeychainManifestEntry(
    entryId: entryId,
    parentFingerprint: parentFingerprint,
    bip85DerivationPath: bip85DerivationPath,
    reservationId: reservationId,
    entryType: entryType,
    ownerFeature: ownerFeature,
    bip85Application: bip85Application,
    bip85Index: bip85Index,
    createdAt: 1,
    updatedAt: 1,
  );
  return KeychainManifestWalletMaterializationRecord(
    entry: entry,
    walletMaterialization: KeychainManifestWalletMaterialization(
      walletId: walletId,
      entryId: entry.entryId,
      childSeedFingerprint: childSeedFingerprint,
      network: network,
      walletPurpose: walletPurpose,
      scriptType: scriptType,
      createdAt: 1,
      updatedAt: 1,
    ),
  );
}

class _InMemoryKeychainManifestStore
    implements KeychainManifestEntryRepository {
  final entries = <KeychainManifestEntry>[];
  final records = <KeychainManifestWalletMaterializationRecord>[];
  String? failOnWalletId;
  bool insertIdenticalRowsBeforeBatch = false;

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
    if (insertIdenticalRowsBeforeBatch) {
      for (final record in records) {
        if (!nextRecords.any((stored) => stored.walletId == record.walletId)) {
          nextRecords.add(record);
          if (!nextEntries.any(
            (entry) => entry.entryId == record.entry.entryId,
          )) {
            nextEntries.add(record.entry);
          }
        }
      }
      insertIdenticalRowsBeforeBatch = false;
    }
    for (final record in records) {
      if (record.walletId == failOnWalletId) {
        throw StateError('insert failed');
      }
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
