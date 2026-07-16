final class WalletMetadataRecordModel {
  final String type;
  final int version;
  final Map<String, Object?> scope;
  final String recordId;
  final Map<String, Object?> payload;

  WalletMetadataRecordModel({
    required this.type,
    required this.version,
    required Map<String, Object?> scope,
    required this.recordId,
    required Map<String, Object?> payload,
  }) : scope = Map.unmodifiable(scope),
       payload = Map.unmodifiable(payload);

  Map<String, Object?> toJson() => {
    'type': type,
    'version': version,
    'scope': scope,
    'recordId': recordId,
    'payload': payload,
  };
}

final class WalletMetadataSectionModel {
  final String type;
  final List<int> versions;
  final int recordCount;
  final String recordsHash;

  WalletMetadataSectionModel({
    required this.type,
    required List<int> versions,
    required this.recordCount,
    required this.recordsHash,
  }) : versions = List.unmodifiable(versions);

  Map<String, Object?> toJson() => {
    'type': type,
    'versions': versions,
    'recordCount': recordCount,
    'recordsHash': recordsHash,
  };
}

final class WalletMetadataChunkReferenceModel {
  final int index;
  final String eventId;
  final String dTag;
  final int recordCount;
  final String ciphertextHash;

  const WalletMetadataChunkReferenceModel({
    required this.index,
    required this.eventId,
    required this.dTag,
    required this.recordCount,
    required this.ciphertextHash,
  });

  Map<String, Object?> toJson() => {
    'index': index,
    'eventId': eventId,
    'd': dTag,
    'recordCount': recordCount,
    'ciphertextHash': ciphertextHash,
  };
}

final class WalletMetadataSnapshotRootModel {
  final String contentType;
  final int envelopeVersion;
  final String parentFingerprint;
  final String snapshotId;
  final int revision;
  final int createdAt;
  final String recordsHash;
  final int recordCount;
  final List<WalletMetadataSectionModel> sections;
  final List<WalletMetadataRecordModel> records;
  final List<WalletMetadataChunkReferenceModel> chunks;

  WalletMetadataSnapshotRootModel({
    required this.contentType,
    required this.envelopeVersion,
    required this.parentFingerprint,
    required this.snapshotId,
    required this.revision,
    required this.createdAt,
    required this.recordsHash,
    required this.recordCount,
    required List<WalletMetadataSectionModel> sections,
    required List<WalletMetadataRecordModel> records,
    required List<WalletMetadataChunkReferenceModel> chunks,
  }) : sections = List.unmodifiable(sections),
       records = List.unmodifiable(records),
       chunks = List.unmodifiable(chunks);

  Map<String, Object?> toJson() => {
    'contentType': contentType,
    'envelopeVersion': envelopeVersion,
    'parentFingerprint': parentFingerprint,
    'snapshotId': snapshotId,
    'revision': revision,
    'createdAt': createdAt,
    'recordsHash': recordsHash,
    'recordCount': recordCount,
    'sections': sections.map((section) => section.toJson()).toList(),
    'records': records.map((record) => record.toJson()).toList(),
    'chunks': chunks.map((chunk) => chunk.toJson()).toList(),
  };
}

final class WalletMetadataSnapshotChunkModel {
  final String contentType;
  final int envelopeVersion;
  final String snapshotId;
  final int index;
  final int chunkCount;
  final int recordCount;
  final List<WalletMetadataRecordModel> records;

  WalletMetadataSnapshotChunkModel({
    required this.contentType,
    required this.envelopeVersion,
    required this.snapshotId,
    required this.index,
    required this.chunkCount,
    required this.recordCount,
    required List<WalletMetadataRecordModel> records,
  }) : records = List.unmodifiable(records);

  Map<String, Object?> toJson() => {
    'contentType': contentType,
    'envelopeVersion': envelopeVersion,
    'snapshotId': snapshotId,
    'index': index,
    'chunkCount': chunkCount,
    'recordCount': recordCount,
    'records': records.map((record) => record.toJson()).toList(),
  };
}
