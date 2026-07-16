import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_nostr_event.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';

final class WalletMetadataEncryptedChunk {
  final WalletMetadataSnapshotChunk plaintext;
  final WalletMetadataNostrEvent event;

  const WalletMetadataEncryptedChunk({
    required this.plaintext,
    required this.event,
  });
}

final class WalletMetadataEncryptedSnapshot {
  final WalletMetadataSnapshotRoot plaintextRoot;
  final WalletMetadataNostrEvent rootEvent;
  final List<WalletMetadataEncryptedChunk> chunks;

  factory WalletMetadataEncryptedSnapshot({
    required WalletMetadataSnapshotRoot plaintextRoot,
    required WalletMetadataNostrEvent rootEvent,
    required List<WalletMetadataEncryptedChunk> chunks,
  }) {
    if (!rootEvent.fitsProductionFrameLimit) {
      throw ArgumentError.value(
        rootEvent.frameByteLength,
        'rootEvent',
        'exceeds the production frame limit',
      );
    }
    if (rootEvent.createdAt != plaintextRoot.createdAt) {
      throw ArgumentError.value(
        rootEvent.createdAt,
        'rootEvent',
        'does not match the root timestamp',
      );
    }
    if (chunks.length != plaintextRoot.chunks.length) {
      throw ArgumentError.value(
        chunks,
        'chunks',
        'does not match the root index',
      );
    }
    final dTags = <String>{rootEvent.dTag};
    for (var index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      final reference = plaintextRoot.chunks[index];
      if (!chunk.event.fitsProductionFrameLimit ||
          chunk.plaintext.index != index ||
          chunk.plaintext.chunkCount != chunks.length ||
          chunk.plaintext.snapshotId != plaintextRoot.snapshotId ||
          chunk.event.authorPublicKeyHex != rootEvent.authorPublicKeyHex ||
          chunk.event.createdAt != rootEvent.createdAt ||
          reference.index != index ||
          reference.eventId != chunk.event.id ||
          reference.dTag != chunk.event.dTag ||
          reference.recordCount != chunk.plaintext.recordCount ||
          reference.ciphertextHash != chunk.event.ciphertextHash) {
        throw ArgumentError.value(
          chunk,
          'chunks',
          'does not match its bounded root reference',
        );
      }
      if (!dTags.add(chunk.event.dTag)) {
        throw ArgumentError.value(
          chunk.event.dTag,
          'chunks',
          'contains a repeated public d tag',
        );
      }
    }
    return WalletMetadataEncryptedSnapshot._(
      plaintextRoot: plaintextRoot,
      rootEvent: rootEvent,
      chunks: List.unmodifiable(chunks),
    );
  }

  const WalletMetadataEncryptedSnapshot._({
    required this.plaintextRoot,
    required this.rootEvent,
    required this.chunks,
  });
}
