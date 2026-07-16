import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_composition_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_inventory.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const repository = WalletMetadataSnapshotCompositionRepositoryImpl();

  test('replaces supported records and preserves unknown remote data', () {
    final oldLabel = _record(
      type: 'labels.bip329',
      version: 1,
      id: 'label-1',
      value: 'old',
    );
    final localLabel = _record(
      type: 'labels.bip329',
      version: 1,
      id: 'label-1',
      value: 'local',
    );
    final newerLabelVersion = _record(
      type: 'labels.bip329',
      version: 2,
      id: 'label-v2',
      value: 'opaque-v2',
    );
    final futureRecord = _record(
      type: 'future.coin_note',
      version: 7,
      id: 'future-1',
      value: 'opaque-future',
    );
    final remote = _remoteHead(
      records: [oldLabel, newerLabelVersion, futureRecord],
      sectionVersions: const {
        'labels.bip329': [1, 2],
        'future.coin_note': [7],
        'future.empty': [3],
      },
    );

    final result = repository.compose(
      contributors: [
        WalletMetadataContributorInventory(
          recordType: 'labels.bip329',
          supportedVersions: const {1},
          records: [localLabel],
        ),
        WalletMetadataContributorInventory(
          recordType: 'wallet.preferences',
          supportedVersions: const {1, 2},
          records: const [],
        ),
      ],
      remoteHead: remote,
    );

    final inventory = _requireOk(result);
    expect(inventory.records.map((record) => record.recordId), [
      'future-1',
      'label-1',
      'label-v2',
    ]);
    expect(
      inventory.records
          .singleWhere((record) => record.recordId == 'label-1')
          .payload['value'],
      'local',
    );
    expect(inventory.records, isNot(contains(oldLabel)));

    final sections = {
      for (final section in inventory.sections) section.type: section,
    };
    expect(sections.keys, {
      'future.coin_note',
      'future.empty',
      'labels.bip329',
      'wallet.preferences',
    });
    expect(sections['future.empty']!.versions, [3]);
    expect(sections['future.empty']!.recordCount, 0);
    expect(sections['labels.bip329']!.versions, [1, 2]);
    expect(sections['wallet.preferences']!.versions, [1, 2]);
    expect(sections['wallet.preferences']!.recordCount, 0);
    expect(
      inventory.canonicalContentHash,
      const WalletMetadataSnapshotCodec().contentHash(
        records: inventory.records,
        sections: inventory.sections,
      ),
    );
  });

  test('content hash changes when an empty supported version is added', () {
    final record = _record(
      type: 'labels.bip329',
      version: 1,
      id: 'label-1',
      value: 'same',
    );
    final remote = _remoteHead(
      records: [record],
      sectionVersions: const {
        'labels.bip329': [1],
      },
    );

    final inventory = _requireOk(
      repository.compose(
        contributors: [
          WalletMetadataContributorInventory(
            recordType: 'labels.bip329',
            supportedVersions: const {1, 2},
            records: [record],
          ),
        ],
        remoteHead: remote,
      ),
    );
    final oldContentHash = const WalletMetadataSnapshotCodec().contentHash(
      records: remote.records,
      sections: remote.root.sections,
    );

    expect(inventory.recordsHash, remote.root.recordsHash);
    expect(inventory.sections.single.versions, [1, 2]);
    expect(inventory.canonicalContentHash, isNot(oldContentHash));
  });

  test('represents a successful all-empty export with a section', () {
    final inventory = _requireOk(
      repository.compose(
        contributors: [
          WalletMetadataContributorInventory(
            recordType: 'wallet.utxo_freeze',
            supportedVersions: const {1},
            records: const [],
          ),
        ],
        remoteHead: null,
      ),
    );

    expect(inventory.isEmpty, isTrue);
    expect(inventory.sections, hasLength(1));
    expect(inventory.sections.single.type, 'wallet.utxo_freeze');
    expect(inventory.sections.single.recordCount, 0);
  });

  test('rejects duplicate contributor type registrations', () {
    final contributor = WalletMetadataContributorInventory(
      recordType: 'labels.bip329',
      supportedVersions: const {1},
      records: const [],
    );

    final result = repository.compose(
      contributors: [contributor, contributor],
      remoteHead: null,
    );

    expect(
      result,
      isA<Err<WalletMetadataSnapshotInventory, WalletMetadataBackupFailure>>(),
    );
    expect((result as Err).failure, isA<WalletMetadataBackupEncodingFailure>());
  });
}

WalletMetadataRecord _record({
  required String type,
  required int version,
  required String id,
  required String value,
}) {
  return WalletMetadataRecord(
    type: type,
    version: version,
    scope: const {'kind': 'global'},
    recordId: id,
    payload: {'value': value},
  );
}

WalletMetadataRemoteHead _remoteHead({
  required List<WalletMetadataRecord> records,
  required Map<String, List<int>> sectionVersions,
}) {
  const codec = WalletMetadataSnapshotCodec();
  final sections = sectionVersions.entries
      .map((entry) {
        final sectionRecords = records
            .where((record) => record.type == entry.key)
            .toList(growable: false);
        return WalletMetadataSection(
          type: entry.key,
          versions: entry.value,
          recordCount: sectionRecords.length,
          recordsHash: codec.recordsHash(sectionRecords),
        );
      })
      .toList(growable: false);
  return WalletMetadataRemoteHead(
    rootEventId: 'a' * 64,
    rootEventCreatedAt: 100,
    highestObservedRootCreatedAt: 100,
    canonicalContentHash: codec.contentHash(
      records: records,
      sections: sections,
    ),
    root: WalletMetadataSnapshotRoot(
      parentFingerprint: '627ef3a6',
      snapshotId: 'b' * 32,
      revision: 4,
      createdAt: 100,
      recordsHash: codec.recordsHash(records),
      recordCount: records.length,
      sections: sections,
      chunks: records.isEmpty
          ? const []
          : [
              WalletMetadataChunkReference(
                index: 0,
                eventId: 'c' * 64,
                dTag: 'd' * 64,
                recordCount: records.length,
                ciphertextHash: 'e' * 64,
              ),
            ],
    ),
    records: records,
  );
}

WalletMetadataSnapshotInventory _requireOk(
  Result<WalletMetadataSnapshotInventory, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}
