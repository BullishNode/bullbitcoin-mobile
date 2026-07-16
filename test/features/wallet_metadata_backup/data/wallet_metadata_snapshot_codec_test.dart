import 'dart:convert';

import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_backup_format_exception.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = WalletMetadataSnapshotCodec();

  test('freezes canonical records, hashes, chunks, and roots', () {
    final records = _records();
    final chunk = _chunk(records);
    final root = _root(codec, records);

    expect(codec.canonicalRecordsJson(records), _canonicalRecords);
    expect(codec.recordsHash([records[1]]), _futureRecordsHash);
    expect(codec.recordsHash([records[0]]), _labelsRecordsHash);
    expect(codec.recordsHash(records), _allRecordsHash);
    expect(codec.encodeChunk(chunk), _chunkGolden);
    expect(codec.encodeRoot(root), _rootGolden);
  });

  test('round trips unknown record types and versions losslessly', () {
    final chunk = codec.decodeChunk(_chunkGolden);
    final root = codec.decodeRoot(_rootGolden);

    expect(chunk.records.first.type, 'future.note');
    expect(chunk.records.first.version, 7);
    expect(chunk.records.first.payload, {
      'a': 1,
      'z': [true, null],
    });
    expect(codec.encodeChunk(chunk), _chunkGolden);
    expect(root.sections.first.type, 'future.note');
    expect(root.sections.first.versions, [7]);
    expect(codec.encodeRoot(root), _rootGolden);
  });

  test('round trips records embedded directly in a root', () {
    final sourceRecords = _records();
    final chunked = _root(codec, sourceRecords);
    final records = sourceRecords..sort();
    final inline = WalletMetadataSnapshotRoot(
      parentFingerprint: chunked.parentFingerprint,
      snapshotId: chunked.snapshotId,
      revision: chunked.revision,
      createdAt: chunked.createdAt,
      recordsHash: chunked.recordsHash,
      recordCount: chunked.recordCount,
      sections: chunked.sections,
      records: records,
      chunks: const [],
    );

    final decoded = codec.decodeRoot(codec.encodeRoot(inline));

    expect(decoded.records.map((record) => record.identity), [
      for (final record in records) record.identity,
    ]);
    expect(decoded.chunks, isEmpty);
    codec.validateRootRecords(root: decoded, records: decoded.records);
  });

  test('rejects roots that mix inline records and chunk references', () {
    final records = _records();
    final chunked = _root(codec, records);

    expect(
      () => WalletMetadataSnapshotRoot(
        parentFingerprint: chunked.parentFingerprint,
        snapshotId: chunked.snapshotId,
        revision: chunked.revision,
        createdAt: chunked.createdAt,
        recordsHash: chunked.recordsHash,
        recordCount: chunked.recordCount,
        sections: chunked.sections,
        records: records,
        chunks: chunked.chunks,
      ),
      throwsArgumentError,
    );
  });

  test(
    'represents a successful all-empty export with sections and no chunks',
    () {
      final emptyHash = codec.recordsHash(const []);
      final root = WalletMetadataSnapshotRoot(
        parentFingerprint: '0123abcd',
        snapshotId: _snapshotId,
        revision: 43,
        createdAt: 1784073601,
        recordsHash: emptyHash,
        recordCount: 0,
        sections: [
          WalletMetadataSection(
            type: 'labels.bip329',
            versions: const [1],
            recordCount: 0,
            recordsHash: emptyHash,
          ),
          WalletMetadataSection(
            type: 'wallet.utxo_freeze',
            versions: const [1],
            recordCount: 0,
            recordsHash: emptyHash,
          ),
        ],
        chunks: const [],
      );

      final encoded = codec.encodeRoot(root);
      final decoded = codec.decodeRoot(encoded);

      expect(decoded.recordCount, 0);
      expect(decoded.sections, hasLength(2));
      expect(decoded.chunks, isEmpty);
    },
  );

  test('checks envelope versions before interpreting root or chunk fields', () {
    expect(
      () => codec.decodeRoot('{"envelopeVersion":2}'),
      throwsA(
        isA<WalletMetadataBackupFormatException>()
            .having(
              (exception) => exception.type,
              'type',
              WalletMetadataBackupFormatExceptionType
                  .unsupportedEnvelopeVersion,
            )
            .having(
              (exception) => exception.envelopeVersion,
              'envelopeVersion',
              2,
            ),
      ),
    );
    _expectFormatFailure(
      () => codec.decodeChunk('{"envelopeVersion":2}'),
      WalletMetadataBackupFormatExceptionType.unsupportedEnvelopeVersion,
    );
    _expectFormatFailure(
      () => codec.decodeRoot('{"envelopeVersion":0}'),
      WalletMetadataBackupFormatExceptionType.malformed,
    );
  });

  test('validates global ordering and root section integrity', () {
    final sourceRecords = _records();
    final records = List<WalletMetadataRecord>.of(sourceRecords)..sort();
    final root = _root(codec, sourceRecords);

    codec.validateRootRecords(root: root, records: records);
    _expectFormatFailure(
      () => codec.validateRootRecords(
        root: root,
        records: records.reversed.toList(growable: false),
      ),
      WalletMetadataBackupFormatExceptionType.malformed,
    );

    final falseSectionRoot = WalletMetadataSnapshotRoot(
      parentFingerprint: root.parentFingerprint,
      snapshotId: root.snapshotId,
      revision: root.revision,
      createdAt: root.createdAt,
      recordsHash: root.recordsHash,
      recordCount: root.recordCount,
      sections: [
        WalletMetadataSection(
          type: 'future.note',
          versions: const [7],
          recordCount: 1,
          recordsHash: 'f' * 64,
        ),
        root.sections.singleWhere((section) => section.type == 'labels.bip329'),
      ],
      chunks: root.chunks,
    );
    _expectFormatFailure(
      () => codec.validateRootRecords(root: falseSectionRoot, records: records),
      WalletMetadataBackupFormatExceptionType.malformed,
    );
  });

  test('rejects duplicate logical record identities', () {
    final decoded = jsonDecode(_chunkGolden) as Map<String, Object?>;
    final records = decoded['records']! as List<Object?>;
    final first = Map<String, Object?>.from(
      records.first! as Map<String, Object?>,
    );
    final duplicate = Map<String, Object?>.from(first)
      ..['payload'] = <String, Object?>{'different': true};
    decoded['records'] = [first, duplicate];
    decoded['recordCount'] = 2;

    _expectFormatFailure(
      () => codec.decodeChunk(jsonEncode(decoded)),
      WalletMetadataBackupFormatExceptionType.malformed,
    );
    final record = _records().first;
    final duplicateRecord = WalletMetadataRecord(
      type: record.type,
      version: record.version,
      scope: record.scope,
      recordId: record.recordId,
      payload: const {'different': true},
    );
    _expectFormatFailure(
      () => codec.recordsHash([record, duplicateRecord]),
      WalletMetadataBackupFormatExceptionType.malformed,
    );
  });

  test(
    'rejects noncanonical ordering, whitespace, and duplicate JSON keys',
    () {
      final decoded = jsonDecode(_chunkGolden) as Map<String, Object?>;
      final records = List<Object?>.from(
        decoded['records']! as List,
      ).reversed.toList(growable: false);
      decoded['records'] = records;
      _expectFormatFailure(
        () => codec.decodeChunk(jsonEncode(decoded)),
        WalletMetadataBackupFormatExceptionType.malformed,
      );
      _expectFormatFailure(
        () => codec.decodeRoot(' $_rootGolden'),
        WalletMetadataBackupFormatExceptionType.malformed,
      );
      _expectFormatFailure(
        () => codec.decodeChunk(
          _chunkGolden.replaceFirst('"index":0', '"index":0,"index":0'),
        ),
        WalletMetadataBackupFormatExceptionType.malformed,
      );
    },
  );

  test('rejects unknown envelope fields and fractional integers', () {
    final root = jsonDecode(_rootGolden) as Map<String, Object?>;
    root['future'] = true;
    _expectFormatFailure(
      () => codec.decodeRoot(jsonEncode(root)),
      WalletMetadataBackupFormatExceptionType.malformed,
    );
    _expectFormatFailure(
      () => codec.decodeChunk(
        _chunkGolden.replaceFirst('"chunkCount":1', '"chunkCount":1.0'),
      ),
      WalletMetadataBackupFormatExceptionType.malformed,
    );
  });

  test('enforces the 64 KiB canonical record limit', () {
    final record = WalletMetadataRecord(
      type: 'future.large',
      version: 1,
      scope: const {},
      recordId: 'large-1',
      payload: {'value': 'x' * 65536},
    );

    _expectFormatFailure(
      () => codec.encodeRecord(record),
      WalletMetadataBackupFormatExceptionType.resourceLimit,
    );
  });

  test('enforces the 12 MiB decrypted document limit before JSON parsing', () {
    final oversized =
        'x' * (WalletMetadataBackupLimits.maxDecryptedSnapshotBytes + 1);

    _expectFormatFailure(
      () => codec.decodeRoot(oversized),
      WalletMetadataBackupFormatExceptionType.resourceLimit,
    );
  });

  test('enforces record and chunk collection ceilings', () {
    final record = _records().first;
    expect(
      () => WalletMetadataSnapshotChunk(
        snapshotId: _snapshotId,
        index: 0,
        chunkCount: 1,
        recordCount: WalletMetadataBackupLimits.maxLogicalRecords + 1,
        records: List.filled(
          WalletMetadataBackupLimits.maxLogicalRecords + 1,
          record,
        ),
      ),
      throwsArgumentError,
    );
    final chunkReference = WalletMetadataChunkReference(
      index: 0,
      eventId: 'b' * 64,
      dTag: 'a' * 64,
      recordCount: 1,
      ciphertextHash: 'c' * 64,
    );
    expect(
      () => WalletMetadataSnapshotRoot(
        parentFingerprint: '0123abcd',
        snapshotId: _snapshotId,
        revision: 1,
        createdAt: 1,
        recordsHash: 'd' * 64,
        recordCount: 1,
        sections: [
          WalletMetadataSection(
            type: 'future.note',
            versions: const [1],
            recordCount: 1,
            recordsHash: 'e' * 64,
          ),
        ],
        chunks: List.filled(
          WalletMetadataBackupLimits.maxChunks + 1,
          chunkReference,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rejects count and index integrity mismatches', () {
    expect(
      () => WalletMetadataSnapshotChunk(
        snapshotId: _snapshotId,
        index: 1,
        chunkCount: 1,
        recordCount: 2,
        records: _records(),
      ),
      throwsArgumentError,
    );
    expect(
      () => WalletMetadataSnapshotRoot(
        parentFingerprint: '0123abcd',
        snapshotId: _snapshotId,
        revision: 1,
        createdAt: 1,
        recordsHash: _allRecordsHash,
        recordCount: 2,
        sections: [
          WalletMetadataSection(
            type: 'future.note',
            versions: const [7],
            recordCount: 1,
            recordsHash: _futureRecordsHash,
          ),
        ],
        chunks: [
          WalletMetadataChunkReference(
            index: 0,
            eventId: 'b' * 64,
            dTag: 'a' * 64,
            recordCount: 2,
            ciphertextHash: 'c' * 64,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}

List<WalletMetadataRecord> _records() {
  return [
    WalletMetadataRecord(
      type: 'labels.bip329',
      version: 1,
      scope: const {
        'walletRef': 'wpkh([0123abcd/84h/0h/0h])',
        'kind': 'wallet',
      },
      recordId:
          'tx:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      payload: const {
        'type': 'tx',
        'ref':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'label': 'salary',
      },
    ),
    WalletMetadataRecord(
      type: 'future.note',
      version: 7,
      scope: const {},
      recordId: 'note-1',
      payload: const {
        'z': [true, null],
        'a': 1,
      },
    ),
  ];
}

WalletMetadataSnapshotChunk _chunk(List<WalletMetadataRecord> records) {
  return WalletMetadataSnapshotChunk(
    snapshotId: _snapshotId,
    index: 0,
    chunkCount: 1,
    recordCount: 2,
    records: records,
  );
}

WalletMetadataSnapshotRoot _root(
  WalletMetadataSnapshotCodec codec,
  List<WalletMetadataRecord> records,
) {
  return WalletMetadataSnapshotRoot(
    parentFingerprint: '0123abcd',
    snapshotId: _snapshotId,
    revision: 42,
    createdAt: 1784073600,
    recordsHash: codec.recordsHash(records),
    recordCount: 2,
    sections: [
      WalletMetadataSection(
        type: 'labels.bip329',
        versions: const [1],
        recordCount: 1,
        recordsHash: codec.recordsHash([records[0]]),
      ),
      WalletMetadataSection(
        type: 'future.note',
        versions: const [7],
        recordCount: 1,
        recordsHash: codec.recordsHash([records[1]]),
      ),
    ],
    chunks: [
      WalletMetadataChunkReference(
        index: 0,
        eventId: 'b' * 64,
        dTag:
            '0123456789abcdef0123456789abcdef'
            '0123456789abcdef0123456789abcdef',
        recordCount: 2,
        ciphertextHash: 'c' * 64,
      ),
    ],
  );
}

void _expectFormatFailure(
  Object? Function() action,
  WalletMetadataBackupFormatExceptionType type,
) {
  expect(
    action,
    throwsA(
      isA<WalletMetadataBackupFormatException>().having(
        (exception) => exception.type,
        'type',
        type,
      ),
    ),
  );
}

const _snapshotId = '00112233445566778899aabbccddeeff';
const _futureRecordsHash =
    '056baf031791d124bb92566f38fa8f357f0dc978d0fbc29a515157b1dc8cff76';
const _labelsRecordsHash =
    '0774d76fb7a64b5e8c97d1782908006df11472eff0ab7da7b09b22640b146166';
const _allRecordsHash =
    'f2b4b47a3c615fc796317c63af511dca5328ab8e145ed661c902f401d36baf85';
const _canonicalRecords =
    '[{"type":"future.note","version":7,"scope":{},"recordId":"note-1",'
    '"payload":{"a":1,"z":[true,null]}},{"type":"labels.bip329",'
    '"version":1,"scope":{"kind":"wallet","walletRef":'
    '"wpkh([0123abcd/84h/0h/0h])"},"recordId":'
    '"tx:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
    '"payload":{"label":"salary","ref":'
    '"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
    '"type":"tx"}}]';
const _chunkGolden =
    '{"contentType":"bullbitcoin.wallet_metadata.chunk","envelopeVersion":1,'
    '"snapshotId":"00112233445566778899aabbccddeeff","index":0,'
    '"chunkCount":1,"recordCount":2,"records":$_canonicalRecords}';
const _rootGolden =
    '{"contentType":"bullbitcoin.wallet_metadata.root","envelopeVersion":1,'
    '"parentFingerprint":"0123abcd","snapshotId":'
    '"00112233445566778899aabbccddeeff","revision":42,'
    '"createdAt":1784073600,"recordsHash":"$_allRecordsHash",'
    '"recordCount":2,"sections":[{"type":"future.note","versions":[7],'
    '"recordCount":1,"recordsHash":"$_futureRecordsHash"},{"type":'
    '"labels.bip329","versions":[1],"recordCount":1,"recordsHash":'
    '"$_labelsRecordsHash"}],"records":[],"chunks":[{"index":0,"eventId":'
    '"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",'
    '"d":"0123456789abcdef0123456789abcdef'
    '0123456789abcdef0123456789abcdef","recordCount":2,'
    '"ciphertextHash":'
    '"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}]}';
