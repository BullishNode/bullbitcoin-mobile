import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_authenticated_cipher.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_key_deriver.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_nostr_event_encoder.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_nostr_event.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = WalletMetadataSnapshotCodec();
  const cipher = RecoverBullNostrAuthenticatedCipher();
  const keyDeriver = WalletMetadataKeyDeriver();

  test('stores a fitting backup in one opaque root event', () {
    const specialLabel =
        'quote " slash \\ newline\n cafe\u0301 \u6771\u4eac \u{1F510}';
    final records = [_record(0, specialLabel), _record(1, 'second annotation')];

    final snapshot = _requireOk(_build(_repository(), records));

    expect(snapshot.chunks, isEmpty);
    expect(snapshot.plaintextRoot.recordCount, records.length);
    expect(snapshot.plaintextRoot.records, records);
    expect(snapshot.plaintextRoot.chunks, isEmpty);
    expect(
      snapshot.rootEvent.dTag,
      '897d29ac2bc6816ccac8963bd9eaef8f0fe0267c9b32efe8c747fed455facf78',
    );
    for (final event in [snapshot.rootEvent]) {
      expect(event.kind, walletMetadataNostrEventKind);
      expect(event.tags, [
        ['d', event.dTag],
      ]);
      expect(event.frameByteLength, utf8.encode(event.serializedFrame).length);
      expect(
        event.frameByteLength,
        lessThanOrEqualTo(WalletMetadataBackupLimits.maxEventFrameBytes),
      );
      expect(event.serializedFrame, isNot(contains(specialLabel)));
      expect(event.serializedFrame, isNot(contains('labels.bip329')));
      expect(event.serializedFrame, isNot(contains('wallet_metadata')));
    }

    final encryptionKey = keyDeriver.deriveEncryptionKey(
      xprvBase58: _masterXprv,
      expectedParentFingerprint: _parentFingerprint,
    );
    final cipherKey = NostrAuthenticatedCipherKey(encryptionKey.hex);
    expect(
      cipher.decrypt(
        ciphertext: NostrAuthenticatedCiphertext(
          snapshot.rootEvent.encryptedContent,
        ),
        key: cipherKey,
      ),
      codec.encodeRoot(snapshot.plaintextRoot),
    );
    expect(snapshot.plaintextRoot.records.first.payload['label'], specialLabel);
  });

  test('chunks only after the measured inline frame exceeds the limit', () {
    final records = [_record(0, 'x' * 10000)];
    final baseline = _requireOk(_build(_repository(), records));
    final inlineFrameBytes = baseline.rootEvent.frameByteLength;
    expect(baseline.chunks, isEmpty);

    final atLimit = _requireOk(
      _build(_repository(maxFrameBytes: inlineFrameBytes), records),
    );
    final belowLimit = _requireOk(
      _build(_repository(maxFrameBytes: inlineFrameBytes - 1), records),
    );

    expect(atLimit.rootEvent.frameByteLength, inlineFrameBytes);
    expect(atLimit.chunks, isEmpty);
    expect(belowLimit.rootEvent.frameByteLength, lessThan(inlineFrameBytes));
    expect(belowLimit.chunks, hasLength(1));
    expect(belowLimit.plaintextRoot.records, isEmpty);
  });

  test(
    'fills a production-size frame until the next complete record cannot fit',
    () {
      expect(WalletMetadataBackupLimits.maxEventFrameBytes, 131000);
      final boundary = _findProductionBoundary();
      final records = [
        _record(0, 'x' * boundary.valueLength),
        _record(1, 'x' * boundary.valueLength),
        _record(2, 'next'),
      ];

      final snapshot = _requireOk(_build(_repository(), records));

      expect(snapshot.chunks, hasLength(2));
      expect(snapshot.chunks.first.plaintext.records, hasLength(2));
      expect(snapshot.chunks.first.event.frameByteLength, 130988);
      expect(boundary.event.frameByteLength, 130988);
      expect(
        WalletMetadataBackupLimits.maxEventFrameBytes -
            snapshot.chunks.first.event.frameByteLength,
        lessThan(32),
      );
      expect(
        boundary.withNextRecord.frameByteLength,
        greaterThan(WalletMetadataBackupLimits.maxEventFrameBytes),
      );

      final oneByteLower = _requireOk(
        _build(
          _repository(
            maxFrameBytes: snapshot.chunks.first.event.frameByteLength - 1,
          ),
          records,
        ),
      );
      expect(oneByteLower.chunks.first.plaintext.records, hasLength(1));
      expect(
        oneByteLower.chunks.first.event.frameByteLength,
        lessThan(snapshot.chunks.first.event.frameByteLength),
      );
    },
  );

  test('random encryption changes bytes without changing chunk boundaries', () {
    final records = List.generate(
      8,
      (index) => _record(index, 'private-${'x' * 18000}'),
    );

    final first = _requireOk(_build(_repository(), records));
    final second = _requireOk(_build(_repository(), records));

    expect(
      first.chunks.map((chunk) => chunk.plaintext.recordCount),
      second.chunks.map((chunk) => chunk.plaintext.recordCount),
    );
    expect(first.plaintextRoot.snapshotId, second.plaintextRoot.snapshotId);
    expect(first.rootEvent.dTag, second.rootEvent.dTag);
    expect(
      first.rootEvent.encryptedContent,
      isNot(second.rootEvent.encryptedContent),
    );
    expect(
      first.chunks.first.event.encryptedContent,
      isNot(second.chunks.first.event.encryptedContent),
    );
  });

  test('returns a typed failure when one complete record cannot fit', () {
    final record = _record(0, 'small but complete');
    final singletonFrameBytes = _chunkFrameFor([record]).frameByteLength;

    final failure = _requireFailure(
      _build(_repository(maxFrameBytes: singletonFrameBytes - 1), [record]),
    );

    expect(failure, isA<WalletMetadataBackupRecordTooLargeFailure>());
    final typed = failure as WalletMetadataBackupRecordTooLargeFailure;
    expect(typed.recordType, record.type);
    expect(typed.maxFrameBytes, singletonFrameBytes - 1);
  });

  test('rejects a root index that exceeds the final frame limit', () {
    final emptyHash = codec.recordsHash(const []);
    final sections = List.generate(
      128,
      (index) => WalletMetadataSection(
        type: 'future.${index.toString().padLeft(3, '0')}.${'x' * 1000}',
        versions: const [1],
        recordCount: 0,
        recordsHash: emptyHash,
      ),
    );

    final failure = _requireFailure(
      _repository().build(
        xprvBase58: _masterXprv,
        parentFingerprint: _parentFingerprint,
        revision: 1,
        createdAt: _createdAt,
        records: const [],
        sections: sections,
      ),
    );

    expect(failure, isA<WalletMetadataBackupRootTooLargeFailure>());
    final typed = failure as WalletMetadataBackupRootTooLargeFailure;
    expect(typed.frameBytes, greaterThan(typed.maxFrameBytes));
    expect(typed.maxFrameBytes, 131000);
  });

  test(
    'accepts 128 chunks and rejects the 129th',
    () {
      final records = List.generate(
        129,
        (index) => _record(index, 'x' * 25000),
      );
      const strictChunkFrameLimit = 65000;

      final accepted = _requireOk(
        _build(
          _repository(maxFrameBytes: strictChunkFrameLimit),
          records.take(128).toList(growable: false),
        ),
      );

      expect(accepted.chunks, hasLength(128));
      expect(accepted.plaintextRoot.chunks, hasLength(128));
      expect(accepted.rootEvent.frameByteLength, lessThanOrEqualTo(65000));
      expect(
        accepted.chunks.every(
          (chunk) =>
              chunk.event.frameByteLength <= strictChunkFrameLimit &&
              chunk.plaintext.recordCount == 1,
        ),
        isTrue,
      );

      final rejected = _requireFailure(
        _build(_repository(maxFrameBytes: strictChunkFrameLimit), records),
      );
      expect(rejected, isA<WalletMetadataBackupChunkLimitFailure>());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('maps key and section composition failures without encrypting', () {
    final record = _record(0, 'label');
    final keyFailure = _requireFailure(
      _repository().build(
        xprvBase58: _masterXprv,
        parentFingerprint: 'ffffffff',
        revision: 1,
        createdAt: _createdAt,
        records: [record],
        sections: _sectionsFor([record]),
      ),
    );
    final wrongSection = WalletMetadataSection(
      type: record.type,
      versions: const [1],
      recordCount: 1,
      recordsHash: 'f' * 64,
    );
    final encodingFailure = _requireFailure(
      _repository().build(
        xprvBase58: _masterXprv,
        parentFingerprint: _parentFingerprint,
        revision: 1,
        createdAt: _createdAt,
        records: [record],
        sections: [wrongSection],
      ),
    );

    expect(keyFailure, isA<WalletMetadataBackupKeyFailure>());
    expect(encodingFailure, isA<WalletMetadataBackupEncodingFailure>());
  });

  test('section versions may include a supported version with no records', () {
    final record = _record(0, 'label');
    const codec = WalletMetadataSnapshotCodec();
    final section = WalletMetadataSection(
      type: record.type,
      versions: const [1, 2],
      recordCount: 1,
      recordsHash: codec.recordsHash([record]),
    );

    final snapshot = _requireOk(
      _repository().build(
        xprvBase58: _masterXprv,
        parentFingerprint: _parentFingerprint,
        revision: 1,
        createdAt: _createdAt,
        records: [record],
        sections: [section],
      ),
    );

    expect(snapshot.plaintextRoot.sections.single.versions, [1, 2]);
  });
}

_BoundaryCandidate _findProductionBoundary() {
  WalletMetadataNostrEvent encode(List<WalletMetadataRecord> records) =>
      _chunkFrameFor(records, chunkCount: 2);

  var low = 1;
  var high = 60000;
  var best = 0;
  while (low <= high) {
    final middle = (low + high) ~/ 2;
    final event = encode([_record(0, 'x' * middle), _record(1, 'x' * middle)]);
    if (event.frameByteLength <=
        WalletMetadataBackupLimits.maxEventFrameBytes) {
      best = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }

  final records = [_record(0, 'x' * best), _record(1, 'x' * best)];
  final event = encode(records);
  final withNextRecord = encode([...records, _record(2, 'next')]);
  return _BoundaryCandidate(
    valueLength: best,
    event: event,
    withNextRecord: withNextRecord,
  );
}

WalletMetadataNostrEvent _chunkFrameFor(
  List<WalletMetadataRecord> records, {
  int chunkCount = 1,
}) {
  const codec = WalletMetadataSnapshotCodec();
  const encoder = WalletMetadataNostrEventEncoder();
  const keyDeriver = WalletMetadataKeyDeriver();
  final key = keyDeriver.deriveEncryptionKey(
    xprvBase58: _masterXprv,
    expectedParentFingerprint: _parentFingerprint,
  );
  final chunk = WalletMetadataSnapshotChunk(
    snapshotId: 'a' * 32,
    index: 0,
    chunkCount: chunkCount,
    recordCount: records.length,
    records: records,
  );
  return encoder.encode(
    plaintext: codec.encodeChunk(chunk),
    dTag: 'b' * 64,
    createdAt: _createdAt,
    encryptionKey: key,
    signer: _nostrIdentity.deriveWalletMetadataSignerFromXprv(_masterXprv),
  );
}

WalletMetadataSnapshotRepositoryImpl _repository({
  int maxFrameBytes = WalletMetadataBackupLimits.maxEventFrameBytes,
}) {
  var counter = 0;
  String deterministicRandomHex(int byteLength) {
    counter++;
    final block = counter.toRadixString(16).padLeft(8, '0');
    return List.filled(
      (byteLength * 2 + 7) ~/ 8,
      block,
    ).join().substring(0, byteLength * 2);
  }

  return WalletMetadataSnapshotRepositoryImpl(
    nostrIdentity: _nostrIdentity,
    maxFrameBytes: maxFrameBytes,
    randomHex: deterministicRandomHex,
  );
}

Result<WalletMetadataEncryptedSnapshot, WalletMetadataBackupFailure> _build(
  WalletMetadataSnapshotRepositoryImpl repository,
  List<WalletMetadataRecord> records,
) {
  return repository.build(
    xprvBase58: _masterXprv,
    parentFingerprint: _parentFingerprint,
    revision: 1,
    createdAt: _createdAt,
    records: records,
    sections: _sectionsFor(records),
  );
}

List<WalletMetadataSection> _sectionsFor(List<WalletMetadataRecord> records) {
  const codec = WalletMetadataSnapshotCodec();
  final grouped = <String, List<WalletMetadataRecord>>{};
  for (final record in records) {
    grouped.putIfAbsent(record.type, () => []).add(record);
  }
  final types = grouped.keys.toList(growable: false)..sort();
  return types
      .map((type) {
        final sectionRecords = grouped[type]!;
        final versions =
            sectionRecords
                .map((record) => record.version)
                .toSet()
                .toList(growable: false)
              ..sort();
        return WalletMetadataSection(
          type: type,
          versions: versions,
          recordCount: sectionRecords.length,
          recordsHash: codec.recordsHash(sectionRecords),
        );
      })
      .toList(growable: false);
}

WalletMetadataRecord _record(int index, String label) {
  return WalletMetadataRecord(
    type: 'labels.bip329',
    version: 1,
    scope: const {'kind': 'global'},
    recordId: 'label-${index.toString().padLeft(5, '0')}',
    payload: {
      'type': 'tx',
      'ref': index.toRadixString(16).padLeft(64, '0'),
      'label': label,
    },
  );
}

T _requireOk<T>(Result<T, WalletMetadataBackupFailure> result) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}

WalletMetadataBackupFailure _requireFailure<T>(
  Result<T, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok() => throw TestFailure('expected failure'),
    Err(:final failure) => failure,
  };
}

final class _BoundaryCandidate {
  final int valueLength;
  final WalletMetadataNostrEvent event;
  final WalletMetadataNostrEvent withNextRecord;

  const _BoundaryCandidate({
    required this.valueLength,
    required this.event,
    required this.withNextRecord,
  });
}

const _nostrIdentity = NostrIdentityFacade(
  deriveHandle: DeriveNostrIdentityHandleUsecase(
    registry: Bip85RegistryFacade(),
  ),
);
const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
const _parentFingerprint = '627ef3a6';
const _createdAt = 1784073600;
