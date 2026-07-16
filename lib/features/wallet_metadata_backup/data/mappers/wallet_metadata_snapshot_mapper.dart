import 'package:bb_mobile/features/wallet_metadata_backup/data/models/wallet_metadata_snapshot_model.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';

abstract final class WalletMetadataSnapshotMapper {
  static WalletMetadataRecordModel recordToModel(WalletMetadataRecord entity) {
    return WalletMetadataRecordModel(
      type: entity.type,
      version: entity.version,
      scope: entity.scope,
      recordId: entity.recordId,
      payload: entity.payload,
    );
  }

  static WalletMetadataRecord recordToEntity(WalletMetadataRecordModel model) {
    return WalletMetadataRecord(
      type: model.type,
      version: model.version,
      scope: model.scope,
      recordId: model.recordId,
      payload: model.payload,
    );
  }

  static WalletMetadataSectionModel sectionToModel(
    WalletMetadataSection entity,
  ) {
    return WalletMetadataSectionModel(
      type: entity.type,
      versions: entity.versions,
      recordCount: entity.recordCount,
      recordsHash: entity.recordsHash,
    );
  }

  static WalletMetadataSection sectionToEntity(
    WalletMetadataSectionModel model,
  ) {
    return WalletMetadataSection(
      type: model.type,
      versions: model.versions,
      recordCount: model.recordCount,
      recordsHash: model.recordsHash,
    );
  }

  static WalletMetadataChunkReferenceModel chunkReferenceToModel(
    WalletMetadataChunkReference entity,
  ) {
    return WalletMetadataChunkReferenceModel(
      index: entity.index,
      eventId: entity.eventId,
      dTag: entity.dTag,
      recordCount: entity.recordCount,
      ciphertextHash: entity.ciphertextHash,
    );
  }

  static WalletMetadataChunkReference chunkReferenceToEntity(
    WalletMetadataChunkReferenceModel model,
  ) {
    return WalletMetadataChunkReference(
      index: model.index,
      eventId: model.eventId,
      dTag: model.dTag,
      recordCount: model.recordCount,
      ciphertextHash: model.ciphertextHash,
    );
  }

  static WalletMetadataSnapshotRootModel rootToModel(
    WalletMetadataSnapshotRoot entity,
  ) {
    return WalletMetadataSnapshotRootModel(
      contentType: entity.contentType,
      envelopeVersion: entity.envelopeVersion,
      parentFingerprint: entity.parentFingerprint,
      snapshotId: entity.snapshotId,
      revision: entity.revision,
      createdAt: entity.createdAt,
      recordsHash: entity.recordsHash,
      recordCount: entity.recordCount,
      sections: entity.sections.map(sectionToModel).toList(growable: false),
      records: entity.records.map(recordToModel).toList(growable: false),
      chunks: entity.chunks.map(chunkReferenceToModel).toList(growable: false),
    );
  }

  static WalletMetadataSnapshotRoot rootToEntity(
    WalletMetadataSnapshotRootModel model,
  ) {
    return WalletMetadataSnapshotRoot(
      contentType: model.contentType,
      envelopeVersion: model.envelopeVersion,
      parentFingerprint: model.parentFingerprint,
      snapshotId: model.snapshotId,
      revision: model.revision,
      createdAt: model.createdAt,
      recordsHash: model.recordsHash,
      recordCount: model.recordCount,
      sections: model.sections.map(sectionToEntity).toList(growable: false),
      records: model.records.map(recordToEntity).toList(growable: false),
      chunks: model.chunks.map(chunkReferenceToEntity).toList(growable: false),
    );
  }

  static WalletMetadataSnapshotChunkModel chunkToModel(
    WalletMetadataSnapshotChunk entity,
  ) {
    return WalletMetadataSnapshotChunkModel(
      contentType: entity.contentType,
      envelopeVersion: entity.envelopeVersion,
      snapshotId: entity.snapshotId,
      index: entity.index,
      chunkCount: entity.chunkCount,
      recordCount: entity.recordCount,
      records: entity.records.map(recordToModel).toList(growable: false),
    );
  }

  static WalletMetadataSnapshotChunk chunkToEntity(
    WalletMetadataSnapshotChunkModel model,
  ) {
    return WalletMetadataSnapshotChunk(
      contentType: model.contentType,
      envelopeVersion: model.envelopeVersion,
      snapshotId: model.snapshotId,
      index: model.index,
      chunkCount: model.chunkCount,
      recordCount: model.recordCount,
      records: model.records.map(recordToEntity).toList(growable: false),
    );
  }
}
