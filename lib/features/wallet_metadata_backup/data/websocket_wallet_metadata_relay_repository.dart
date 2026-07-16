import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_relay_transport.dart';
import 'package:bb_mobile/core/nostr/nostr_signed_event.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_nostr_event.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_relay_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:meta/meta.dart';

final class WebSocketWalletMetadataRelayRepository
    implements WalletMetadataRelayRepository {
  final NostrRelayTransport _transport;
  final Duration _timeout;

  const WebSocketWalletMetadataRelayRepository({
    this._transport = const NostrRelayTransport(),
    this._timeout = const Duration(seconds: 10),
  });

  @override
  @useResult
  Future<Result<WalletMetadataSnapshotPublication, WalletMetadataBackupFailure>>
  publishAndVerify({
    required WalletMetadataEncryptedSnapshot snapshot,
    required List<WalletMetadataRelayUrl> relayUrls,
  }) async {
    if (relayUrls.isEmpty) {
      return const Err(WalletMetadataBackupRelayFailure());
    }
    final uniqueRelays = relayUrls.toSet().toList(growable: false);
    if (uniqueRelays.length > WalletMetadataBackupLimits.maxRelays) {
      return const Err(WalletMetadataBackupResourceLimitFailure());
    }
    try {
      final outcomes = await Future.wait(
        uniqueRelays.map(
          (relayUrl) => _publishToRelay(snapshot: snapshot, relayUrl: relayUrl),
        ),
      );
      return Ok(WalletMetadataSnapshotPublication(relayOutcomes: outcomes));
    } on Exception {
      return const Err(WalletMetadataBackupRelayFailure());
    }
  }

  Future<WalletMetadataRelayReplicaOutcome> _publishToRelay({
    required WalletMetadataEncryptedSnapshot snapshot,
    required WalletMetadataRelayUrl relayUrl,
  }) async {
    var acceptedChunks = 0;
    var contactedRelay = false;
    for (final chunk in snapshot.chunks) {
      final outcome = await _transport.publish(
        relayUri: relayUrl.uri,
        eventMessage: chunk.event.serializedFrame,
        eventId: chunk.event.id,
        timeout: _timeout,
      );
      contactedRelay = contactedRelay || outcome.contactedRelay;
      if (!outcome.accepted) {
        return WalletMetadataRelayReplicaOutcome(
          relayUrl: relayUrl,
          status: WalletMetadataRelayReplicaStatus.chunksNotAccepted,
          acceptedChunkCount: acceptedChunks,
          expectedChunkCount: snapshot.chunks.length,
          contactedRelay: contactedRelay,
        );
      }
      acceptedChunks++;
    }

    final rootOutcome = await _transport.publish(
      relayUri: relayUrl.uri,
      eventMessage: snapshot.rootEvent.serializedFrame,
      eventId: snapshot.rootEvent.id,
      timeout: _timeout,
    );
    contactedRelay = contactedRelay || rootOutcome.contactedRelay;
    if (!rootOutcome.accepted) {
      return WalletMetadataRelayReplicaOutcome(
        relayUrl: relayUrl,
        status: WalletMetadataRelayReplicaStatus.rootNotAccepted,
        acceptedChunkCount: acceptedChunks,
        expectedChunkCount: snapshot.chunks.length,
        contactedRelay: contactedRelay,
      );
    }

    final verified = await _readBackExactSnapshot(
      snapshot: snapshot,
      relayUrl: relayUrl,
    );
    return WalletMetadataRelayReplicaOutcome(
      relayUrl: relayUrl,
      status: verified
          ? WalletMetadataRelayReplicaStatus.verified
          : WalletMetadataRelayReplicaStatus.acceptedUnverified,
      acceptedChunkCount: acceptedChunks,
      expectedChunkCount: snapshot.chunks.length,
      contactedRelay: contactedRelay,
    );
  }

  Future<bool> _readBackExactSnapshot({
    required WalletMetadataEncryptedSnapshot snapshot,
    required WalletMetadataRelayUrl relayUrl,
  }) async {
    final expected = [
      snapshot.rootEvent,
      ...snapshot.chunks.map((chunk) => chunk.event),
    ];
    final subscriptionId =
        'wm-verify-${snapshot.rootEvent.id.substring(0, 16)}';
    final outcome = await _transport.fetch(
      relayUri: relayUrl.uri,
      requestMessage: jsonEncode([
        'REQ',
        subscriptionId,
        {
          'ids': expected.map((event) => event.id).toList(growable: false),
          'authors': [snapshot.rootEvent.authorPublicKeyHex],
          'kinds': [walletMetadataNostrEventKind],
          'limit': expected.length,
        },
      ]),
      subscriptionId: subscriptionId,
      limit: expected.length,
      maxFrameBytes:
          WalletMetadataBackupLimits.maxEventFrameBytes +
          WalletMetadataBackupLimits.maxRelayResponseFrameAllowance,
      timeout: _timeout,
    );
    if (outcome.status != NostrRelayFetchStatus.completed) return false;

    final actualFramesById = <String, String>{};
    for (final relayEvent in outcome.events) {
      try {
        final signed = const NostrSignedEventCodec().fromNostrEvent(relayEvent);
        actualFramesById[signed.id] = const NostrSignedEventCodec().serialize(
          signed,
        );
      } on Exception {
        return false;
      }
    }
    for (final expectedEvent in expected) {
      final actualFrame = actualFramesById[expectedEvent.id];
      if (actualFrame == null || actualFrame != expectedEvent.serializedFrame) {
        return false;
      }
    }
    return true;
  }
}
