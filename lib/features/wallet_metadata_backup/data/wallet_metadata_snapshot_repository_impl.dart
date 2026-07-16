import 'dart:convert';
import 'dart:math';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_backup_format_exception.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_key_deriver.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_nostr_event_encoder.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encryption_key.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_nostr_event.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_snapshot_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:hex/hex.dart';
import 'package:meta/meta.dart';

typedef WalletMetadataRandomHex = String Function(int byteLength);

final class WalletMetadataSnapshotRepositoryImpl
    implements WalletMetadataSnapshotRepository {
  final NostrIdentityFacade nostrIdentity;
  final WalletMetadataSnapshotCodec codec;
  final WalletMetadataKeyDeriver keyDeriver;
  final WalletMetadataNostrEventEncoder eventEncoder;
  final int maxFrameBytes;
  final WalletMetadataRandomHex _randomHex;

  WalletMetadataSnapshotRepositoryImpl({
    required this.nostrIdentity,
    this.codec = const WalletMetadataSnapshotCodec(),
    this.keyDeriver = const WalletMetadataKeyDeriver(),
    this.eventEncoder = const WalletMetadataNostrEventEncoder(),
    this.maxFrameBytes = WalletMetadataBackupLimits.maxEventFrameBytes,
    WalletMetadataRandomHex? randomHex,
  }) : _randomHex = randomHex ?? _secureRandomHex {
    if (maxFrameBytes <= 0 ||
        maxFrameBytes > WalletMetadataBackupLimits.maxEventFrameBytes) {
      throw ArgumentError.value(
        maxFrameBytes,
        'maxFrameBytes',
        'must be inside the production event-frame limit',
      );
    }
  }

  @override
  @useResult
  Result<WalletMetadataEncryptedSnapshot, WalletMetadataBackupFailure> build({
    required String xprvBase58,
    required String parentFingerprint,
    required int revision,
    required int createdAt,
    required List<WalletMetadataRecord> records,
    required List<WalletMetadataSection> sections,
  }) {
    try {
      final encryptionKey = keyDeriver.deriveEncryptionKey(
        xprvBase58: xprvBase58,
        expectedParentFingerprint: parentFingerprint,
      );
      final signer = nostrIdentity.deriveWalletMetadataSignerFromXprv(
        xprvBase58,
      );
      final sortedRecords = List<WalletMetadataRecord>.of(records)..sort();
      codec.canonicalRecordsJson(sortedRecords);
      _validateSections(sortedRecords, sections);

      final rootDTag = keyDeriver.deriveRootDTag(encryptionKey);
      final snapshotId = _randomHexValue(16);
      final normalizedFingerprint = parentFingerprint.trim().toLowerCase();
      final recordsHash = codec.recordsHash(sortedRecords);
      final inlineRoot = WalletMetadataSnapshotRoot(
        parentFingerprint: normalizedFingerprint,
        snapshotId: snapshotId,
        revision: revision,
        createdAt: createdAt,
        recordsHash: recordsHash,
        recordCount: sortedRecords.length,
        sections: sections,
        records: sortedRecords,
        chunks: const [],
      );
      final inlineRootPlaintext = codec.encodeRoot(inlineRoot);
      final inlineRootEvent = eventEncoder.encode(
        plaintext: inlineRootPlaintext,
        dTag: rootDTag,
        createdAt: createdAt,
        encryptionKey: encryptionKey,
        signer: signer,
      );
      if (inlineRootEvent.frameByteLength <= maxFrameBytes) {
        return Ok(
          WalletMetadataEncryptedSnapshot(
            plaintextRoot: inlineRoot,
            rootEvent: inlineRootEvent,
            chunks: const [],
          ),
        );
      }

      final chunkDTags = _ChunkDTagCache(
        randomHex: _randomHex,
        initiallyUsed: {rootDTag},
      );
      final chunks = _buildFinalChunks(
        records: sortedRecords,
        snapshotId: snapshotId,
        createdAt: createdAt,
        encryptionKey: encryptionKey,
        signer: signer,
        dTags: chunkDTags,
      );
      final references = chunks
          .map(
            (chunk) => WalletMetadataChunkReference(
              index: chunk.plaintext.index,
              eventId: chunk.event.id,
              dTag: chunk.event.dTag,
              recordCount: chunk.plaintext.recordCount,
              ciphertextHash: chunk.event.ciphertextHash,
            ),
          )
          .toList(growable: false);
      final root = WalletMetadataSnapshotRoot(
        parentFingerprint: normalizedFingerprint,
        snapshotId: snapshotId,
        revision: revision,
        createdAt: createdAt,
        recordsHash: recordsHash,
        recordCount: sortedRecords.length,
        sections: sections,
        records: const [],
        chunks: references,
      );
      final rootPlaintext = codec.encodeRoot(root);
      final rootEvent = eventEncoder.encode(
        plaintext: rootPlaintext,
        dTag: rootDTag,
        createdAt: createdAt,
        encryptionKey: encryptionKey,
        signer: signer,
      );
      if (rootEvent.frameByteLength > maxFrameBytes) {
        throw _RootTooLargeException(rootEvent.frameByteLength);
      }
      final totalPlaintextBytes =
          utf8.encode(rootPlaintext).length +
          chunks.fold<int>(0, (sum, chunk) => sum + chunk.plaintextBytes);
      if (totalPlaintextBytes >
          WalletMetadataBackupLimits.maxDecryptedSnapshotBytes) {
        throw const _AggregateResourceLimitException();
      }

      return Ok(
        WalletMetadataEncryptedSnapshot(
          plaintextRoot: root,
          rootEvent: rootEvent,
          chunks: chunks
              .map(
                (chunk) => WalletMetadataEncryptedChunk(
                  plaintext: chunk.plaintext,
                  event: chunk.event,
                ),
              )
              .toList(growable: false),
        ),
      );
    } on WalletMetadataKeyDerivationException {
      return const Err(WalletMetadataBackupKeyFailure());
    } on WalletMetadataBackupFormatException catch (e) {
      if (e.type == WalletMetadataBackupFormatExceptionType.resourceLimit) {
        return const Err(WalletMetadataBackupResourceLimitFailure());
      }
      return const Err(WalletMetadataBackupEncodingFailure());
    } on WalletMetadataNostrEventEncodingException {
      return const Err(WalletMetadataBackupEncodingFailure());
    } on _SnapshotCompositionException {
      return const Err(WalletMetadataBackupEncodingFailure());
    } on _RecordTooLargeException catch (e) {
      return Err(
        WalletMetadataBackupRecordTooLargeFailure(
          recordType: e.recordType,
          maxFrameBytes: maxFrameBytes,
        ),
      );
    } on _ChunkLimitException {
      return const Err(
        WalletMetadataBackupChunkLimitFailure(
          maxChunks: WalletMetadataBackupLimits.maxChunks,
        ),
      );
    } on _RootTooLargeException catch (e) {
      return Err(
        WalletMetadataBackupRootTooLargeFailure(
          frameBytes: e.frameBytes,
          maxFrameBytes: maxFrameBytes,
        ),
      );
    } on _AggregateResourceLimitException {
      return const Err(WalletMetadataBackupResourceLimitFailure());
    } on _RandomSourceException {
      return const Err(WalletMetadataBackupEncodingFailure());
    }
  }

  List<_BuiltChunk> _buildFinalChunks({
    required List<WalletMetadataRecord> records,
    required String snapshotId,
    required int createdAt,
    required WalletMetadataEncryptionKey encryptionKey,
    required WalletMetadataNostrSigner signer,
    required _ChunkDTagCache dTags,
  }) {
    if (records.isEmpty) return const [];

    for (final widthCeiling in const [9, 99, 128]) {
      try {
        var assumedChunkCount = widthCeiling;
        while (true) {
          final chunks = _partition(
            records: records,
            snapshotId: snapshotId,
            assumedChunkCount: assumedChunkCount,
            createdAt: createdAt,
            encryptionKey: encryptionKey,
            signer: signer,
            dTags: dTags,
          );
          if (chunks.length == assumedChunkCount) return chunks;
          assumedChunkCount = chunks.length;
        }
      } on _ChunkCountAssumptionTooSmallException {
        continue;
      }
    }
    throw const _ChunkLimitException();
  }

  List<_BuiltChunk> _partition({
    required List<WalletMetadataRecord> records,
    required String snapshotId,
    required int assumedChunkCount,
    required int createdAt,
    required WalletMetadataEncryptionKey encryptionKey,
    required WalletMetadataNostrSigner signer,
    required _ChunkDTagCache dTags,
  }) {
    final chunks = <_BuiltChunk>[];
    var firstRecord = 0;

    while (firstRecord < records.length) {
      if (chunks.length >= assumedChunkCount) {
        if (assumedChunkCount < WalletMetadataBackupLimits.maxChunks) {
          throw const _ChunkCountAssumptionTooSmallException();
        }
        throw const _ChunkLimitException();
      }

      _BuiltChunk? accepted;
      var acceptedEnd = firstRecord;
      int? rejectedEnd;
      var probeSize = 1;
      while (true) {
        final endExclusive = min(firstRecord + probeSize, records.length);
        final candidate = _encodeChunk(
          records: records.sublist(firstRecord, endExclusive),
          snapshotId: snapshotId,
          index: chunks.length,
          chunkCount: assumedChunkCount,
          createdAt: createdAt,
          encryptionKey: encryptionKey,
          signer: signer,
          dTag: dTags.at(chunks.length),
        );
        if (candidate.event.frameByteLength > maxFrameBytes) {
          rejectedEnd = endExclusive;
          break;
        }
        accepted = candidate;
        acceptedEnd = endExclusive;
        if (endExclusive == records.length) break;
        probeSize *= 2;
      }

      var low = acceptedEnd + 1;
      var high = (rejectedEnd ?? acceptedEnd) - 1;
      while (low <= high) {
        final endExclusive = (low + high) ~/ 2;
        final candidate = _encodeChunk(
          records: records.sublist(firstRecord, endExclusive),
          snapshotId: snapshotId,
          index: chunks.length,
          chunkCount: assumedChunkCount,
          createdAt: createdAt,
          encryptionKey: encryptionKey,
          signer: signer,
          dTag: dTags.at(chunks.length),
        );
        if (candidate.event.frameByteLength <= maxFrameBytes) {
          accepted = candidate;
          low = endExclusive + 1;
        } else {
          high = endExclusive - 1;
        }
      }

      if (accepted == null) {
        throw _RecordTooLargeException(records[firstRecord].type);
      }
      chunks.add(accepted);
      firstRecord += accepted.plaintext.recordCount;
    }
    return chunks;
  }

  _BuiltChunk _encodeChunk({
    required List<WalletMetadataRecord> records,
    required String snapshotId,
    required int index,
    required int chunkCount,
    required int createdAt,
    required WalletMetadataEncryptionKey encryptionKey,
    required WalletMetadataNostrSigner signer,
    required String dTag,
  }) {
    final chunk = WalletMetadataSnapshotChunk(
      snapshotId: snapshotId,
      index: index,
      chunkCount: chunkCount,
      recordCount: records.length,
      records: records,
    );
    final plaintext = codec.encodeChunk(chunk);
    return _BuiltChunk(
      plaintext: chunk,
      event: eventEncoder.encode(
        plaintext: plaintext,
        dTag: dTag,
        createdAt: createdAt,
        encryptionKey: encryptionKey,
        signer: signer,
      ),
      plaintextBytes: utf8.encode(plaintext).length,
    );
  }

  void _validateSections(
    List<WalletMetadataRecord> records,
    List<WalletMetadataSection> sections,
  ) {
    final recordsByType = <String, List<WalletMetadataRecord>>{};
    for (final record in records) {
      recordsByType.putIfAbsent(record.type, () => []).add(record);
    }
    final sectionTypes = <String>{};
    for (final section in sections) {
      if (!sectionTypes.add(section.type)) {
        throw const _SnapshotCompositionException();
      }
      final sectionRecords = recordsByType.remove(section.type) ?? const [];
      final versions =
          sectionRecords
              .map((record) => record.version)
              .toSet()
              .toList(growable: false)
            ..sort();
      if (section.recordCount != sectionRecords.length ||
          section.recordsHash != codec.recordsHash(sectionRecords) ||
          versions.any((version) => !section.versions.contains(version))) {
        throw const _SnapshotCompositionException();
      }
    }
    if (recordsByType.isNotEmpty) {
      throw const _SnapshotCompositionException();
    }
  }

  String _randomHexValue(int byteLength) {
    final value = _randomHex(byteLength);
    if (!RegExp('^[0-9a-f]{${byteLength * 2}}\$').hasMatch(value)) {
      throw const _RandomSourceException();
    }
    return value;
  }

  static String _secureRandomHex(int byteLength) {
    final random = Random.secure();
    return HEX.encode(
      List<int>.generate(byteLength, (_) => random.nextInt(256)),
    );
  }
}

final class _ChunkDTagCache {
  final WalletMetadataRandomHex randomHex;
  final Set<String> _used;
  final List<String> _tags = [];

  _ChunkDTagCache({required this.randomHex, required Set<String> initiallyUsed})
    : _used = Set.of(initiallyUsed);

  String at(int index) {
    while (_tags.length <= index) {
      String? candidate;
      for (var attempt = 0; attempt < 8; attempt++) {
        final value = randomHex(32);
        if (RegExp(r'^[0-9a-f]{64}$').hasMatch(value) && _used.add(value)) {
          candidate = value;
          break;
        }
      }
      if (candidate == null) {
        throw const _RandomSourceException();
      }
      _tags.add(candidate);
    }
    return _tags[index];
  }
}

final class _BuiltChunk {
  final WalletMetadataSnapshotChunk plaintext;
  final WalletMetadataNostrEvent event;
  final int plaintextBytes;

  const _BuiltChunk({
    required this.plaintext,
    required this.event,
    required this.plaintextBytes,
  });
}

final class _SnapshotCompositionException implements Exception {
  const _SnapshotCompositionException();
}

final class _RecordTooLargeException implements Exception {
  final String recordType;

  const _RecordTooLargeException(this.recordType);
}

final class _ChunkLimitException implements Exception {
  const _ChunkLimitException();
}

final class _ChunkCountAssumptionTooSmallException implements Exception {
  const _ChunkCountAssumptionTooSmallException();
}

final class _RootTooLargeException implements Exception {
  final int frameBytes;

  const _RootTooLargeException(this.frameBytes);
}

final class _AggregateResourceLimitException implements Exception {
  const _AggregateResourceLimitException();
}

final class _RandomSourceException implements Exception {
  const _RandomSourceException();
}
