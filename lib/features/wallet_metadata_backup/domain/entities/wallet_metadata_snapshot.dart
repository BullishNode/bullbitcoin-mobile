import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_json.dart';

const int walletMetadataEnvelopeVersion = 1;
const String walletMetadataRootContentType = 'bullbitcoin.wallet_metadata.root';
const String walletMetadataChunkContentType =
    'bullbitcoin.wallet_metadata.chunk';

final RegExp _fingerprintPattern = RegExp(r'^[0-9a-f]{8}$');
final RegExp _snapshotIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _hashPattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _opaqueTagPattern = RegExp(r'^[0-9a-f]{64}$');

final class WalletMetadataSection {
  final String type;
  final List<int> versions;
  final int recordCount;
  final String recordsHash;

  factory WalletMetadataSection({
    required String type,
    required List<int> versions,
    required int recordCount,
    required String recordsHash,
  }) {
    if (versions.isEmpty) {
      throw ArgumentError.value(versions, 'versions', 'must not be empty');
    }
    if (versions.length > WalletMetadataBackupLimits.maxLogicalRecords) {
      throw ArgumentError.value(
        versions.length,
        'versions',
        'too many versions',
      );
    }
    final sortedVersions = List<int>.of(versions)..sort();
    if (sortedVersions.any(
      (version) =>
          version <= 0 || version > WalletMetadataBackupLimits.maxSignedInt64,
    )) {
      throw ArgumentError.value(
        versions,
        'versions',
        'must be positive int64 values',
      );
    }
    if (sortedVersions.toSet().length != sortedVersions.length) {
      throw ArgumentError.value(versions, 'versions', 'must be unique');
    }
    _validateRecordCount(recordCount);
    _validateHash(recordsHash, 'recordsHash');
    return WalletMetadataSection._(
      type: walletMetadataValidateString(type, name: 'type', allowEmpty: false),
      versions: List.unmodifiable(sortedVersions),
      recordCount: recordCount,
      recordsHash: recordsHash,
    );
  }

  const WalletMetadataSection._({
    required this.type,
    required this.versions,
    required this.recordCount,
    required this.recordsHash,
  });
}

final class WalletMetadataChunkReference {
  final int index;
  final String eventId;
  final String dTag;
  final int recordCount;
  final String ciphertextHash;

  WalletMetadataChunkReference({
    required this.index,
    required this.eventId,
    required this.dTag,
    required this.recordCount,
    required this.ciphertextHash,
  }) {
    if (index < 0 || index >= WalletMetadataBackupLimits.maxChunks) {
      throw ArgumentError.value(index, 'index', 'is outside the chunk limit');
    }
    _validateHash(eventId, 'eventId');
    if (!_opaqueTagPattern.hasMatch(dTag)) {
      throw ArgumentError.value(dTag, 'd', 'must be lowercase 32-byte hex');
    }
    _validateRecordCount(recordCount, allowZero: false);
    _validateHash(ciphertextHash, 'ciphertextHash');
  }
}

final class WalletMetadataSnapshotRoot {
  final String contentType;
  final int envelopeVersion;
  final String parentFingerprint;
  final String snapshotId;
  final int revision;
  final int createdAt;
  final String recordsHash;
  final int recordCount;
  final List<WalletMetadataSection> sections;
  final List<WalletMetadataRecord> records;
  final List<WalletMetadataChunkReference> chunks;

  factory WalletMetadataSnapshotRoot({
    String contentType = walletMetadataRootContentType,
    int envelopeVersion = walletMetadataEnvelopeVersion,
    required String parentFingerprint,
    required String snapshotId,
    required int revision,
    required int createdAt,
    required String recordsHash,
    required int recordCount,
    required List<WalletMetadataSection> sections,
    List<WalletMetadataRecord> records = const [],
    required List<WalletMetadataChunkReference> chunks,
  }) {
    _validateEnvelopeHeader(
      contentType: contentType,
      expectedContentType: walletMetadataRootContentType,
      envelopeVersion: envelopeVersion,
    );
    if (!_fingerprintPattern.hasMatch(parentFingerprint)) {
      throw ArgumentError.value(
        parentFingerprint,
        'parentFingerprint',
        'must be lowercase 4-byte hex',
      );
    }
    _validateSnapshotId(snapshotId);
    _validateNonNegativeInt64(revision, 'revision');
    _validateNonNegativeInt64(createdAt, 'createdAt');
    _validateHash(recordsHash, 'recordsHash');
    _validateRecordCount(recordCount);
    if (sections.length > WalletMetadataBackupLimits.maxLogicalRecords) {
      throw ArgumentError.value(
        sections.length,
        'sections',
        'too many sections',
      );
    }
    if (chunks.length > WalletMetadataBackupLimits.maxChunks) {
      throw ArgumentError.value(chunks.length, 'chunks', 'too many chunks');
    }
    if (records.length > WalletMetadataBackupLimits.maxLogicalRecords) {
      throw ArgumentError.value(records.length, 'records', 'too many records');
    }
    final sortedSections = List<WalletMetadataSection>.of(sections)
      ..sort((a, b) => a.type.compareTo(b.type));
    if (sortedSections.map((section) => section.type).toSet().length !=
        sortedSections.length) {
      throw ArgumentError.value(sections, 'sections', 'duplicate section type');
    }
    final sectionRecordCount = sortedSections.fold<int>(
      0,
      (sum, section) => sum + section.recordCount,
    );
    if (sectionRecordCount != recordCount) {
      throw ArgumentError.value(
        recordCount,
        'recordCount',
        'does not match section counts',
      );
    }
    final sortedChunks = List<WalletMetadataChunkReference>.of(chunks)
      ..sort((a, b) => a.index.compareTo(b.index));
    final sortedRecords = List<WalletMetadataRecord>.of(records)..sort();
    if (sortedRecords.map((record) => record.identity).toSet().length !=
        sortedRecords.length) {
      throw ArgumentError.value(
        records,
        'records',
        'duplicate record identity',
      );
    }
    if (sortedRecords.isNotEmpty && sortedChunks.isNotEmpty) {
      throw ArgumentError(
        'wallet metadata root cannot contain records and chunk references',
      );
    }
    for (var index = 0; index < sortedChunks.length; index++) {
      if (sortedChunks[index].index != index) {
        throw ArgumentError.value(
          chunks,
          'chunks',
          'indexes must be contiguous',
        );
      }
    }
    if (sortedRecords.isNotEmpty) {
      if (sortedRecords.length != recordCount) {
        throw ArgumentError.value(
          recordCount,
          'recordCount',
          'does not match inline records',
        );
      }
    } else {
      final chunkRecordCount = sortedChunks.fold<int>(
        0,
        (sum, chunk) => sum + chunk.recordCount,
      );
      if (chunkRecordCount != recordCount) {
        throw ArgumentError.value(
          recordCount,
          'recordCount',
          'does not match chunk counts',
        );
      }
      if (recordCount > 0 && sortedChunks.isEmpty) {
        throw ArgumentError.value(chunks, 'chunks', 'records require storage');
      }
    }
    return WalletMetadataSnapshotRoot._(
      contentType: contentType,
      envelopeVersion: envelopeVersion,
      parentFingerprint: parentFingerprint,
      snapshotId: snapshotId,
      revision: revision,
      createdAt: createdAt,
      recordsHash: recordsHash,
      recordCount: recordCount,
      sections: List.unmodifiable(sortedSections),
      records: List.unmodifiable(sortedRecords),
      chunks: List.unmodifiable(sortedChunks),
    );
  }

  const WalletMetadataSnapshotRoot._({
    required this.contentType,
    required this.envelopeVersion,
    required this.parentFingerprint,
    required this.snapshotId,
    required this.revision,
    required this.createdAt,
    required this.recordsHash,
    required this.recordCount,
    required this.sections,
    required this.records,
    required this.chunks,
  });
}

final class WalletMetadataSnapshotChunk {
  final String contentType;
  final int envelopeVersion;
  final String snapshotId;
  final int index;
  final int chunkCount;
  final int recordCount;
  final List<WalletMetadataRecord> records;

  factory WalletMetadataSnapshotChunk({
    String contentType = walletMetadataChunkContentType,
    int envelopeVersion = walletMetadataEnvelopeVersion,
    required String snapshotId,
    required int index,
    required int chunkCount,
    required int recordCount,
    required List<WalletMetadataRecord> records,
  }) {
    _validateEnvelopeHeader(
      contentType: contentType,
      expectedContentType: walletMetadataChunkContentType,
      envelopeVersion: envelopeVersion,
    );
    _validateSnapshotId(snapshotId);
    if (chunkCount <= 0 || chunkCount > WalletMetadataBackupLimits.maxChunks) {
      throw ArgumentError.value(
        chunkCount,
        'chunkCount',
        'is outside the chunk limit',
      );
    }
    if (index < 0 || index >= chunkCount) {
      throw ArgumentError.value(index, 'index', 'must be inside chunkCount');
    }
    if (records.isEmpty) {
      throw ArgumentError.value(records, 'records', 'must not be empty');
    }
    if (records.length > WalletMetadataBackupLimits.maxLogicalRecords) {
      throw ArgumentError.value(records.length, 'records', 'too many records');
    }
    _validateRecordCount(recordCount, allowZero: false);
    if (recordCount != records.length) {
      throw ArgumentError.value(
        recordCount,
        'recordCount',
        'does not match records',
      );
    }
    final sortedRecords = List<WalletMetadataRecord>.of(records)..sort();
    final identities = <String>{};
    for (final record in sortedRecords) {
      if (!identities.add(record.identity)) {
        throw ArgumentError.value(
          records,
          'records',
          'duplicate record identity',
        );
      }
    }
    return WalletMetadataSnapshotChunk._(
      contentType: contentType,
      envelopeVersion: envelopeVersion,
      snapshotId: snapshotId,
      index: index,
      chunkCount: chunkCount,
      recordCount: recordCount,
      records: List.unmodifiable(sortedRecords),
    );
  }

  const WalletMetadataSnapshotChunk._({
    required this.contentType,
    required this.envelopeVersion,
    required this.snapshotId,
    required this.index,
    required this.chunkCount,
    required this.recordCount,
    required this.records,
  });
}

void _validateEnvelopeHeader({
  required String contentType,
  required String expectedContentType,
  required int envelopeVersion,
}) {
  if (contentType != expectedContentType) {
    throw ArgumentError.value(contentType, 'contentType', 'is unsupported');
  }
  if (envelopeVersion != walletMetadataEnvelopeVersion) {
    throw ArgumentError.value(
      envelopeVersion,
      'envelopeVersion',
      'is unsupported',
    );
  }
}

void _validateSnapshotId(String snapshotId) {
  if (!_snapshotIdPattern.hasMatch(snapshotId)) {
    throw ArgumentError.value(
      snapshotId,
      'snapshotId',
      'must be lowercase 128-bit hex',
    );
  }
}

void _validateHash(String value, String name) {
  if (!_hashPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be lowercase 32-byte hex');
  }
}

void _validateRecordCount(int value, {bool allowZero = true}) {
  final minimum = allowZero ? 0 : 1;
  if (value < minimum || value > WalletMetadataBackupLimits.maxLogicalRecords) {
    throw ArgumentError.value(
      value,
      'recordCount',
      'is outside the record limit',
    );
  }
}

void _validateNonNegativeInt64(int value, String name) {
  if (value < 0 || value > WalletMetadataBackupLimits.maxSignedInt64) {
    throw ArgumentError.value(value, name, 'must be a non-negative int64');
  }
}
