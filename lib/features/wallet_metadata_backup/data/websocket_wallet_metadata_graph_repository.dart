import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_authenticated_cipher.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_transport.dart';
import 'package:bb_mobile/core/nostr/nostr_signed_event.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_backup_format_exception.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_key_deriver.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encryption_key.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_graph_scan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_nostr_event.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_graph_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:meta/meta.dart';
import 'package:nostr/nostr.dart' as nostr;

final class WebSocketWalletMetadataGraphRepository
    implements WalletMetadataGraphRepository {
  final NostrRelayTransport _transport;
  final NostrIdentityFacade _nostrIdentity;
  final WalletMetadataKeyDeriver _keyDeriver;
  final WalletMetadataSnapshotCodec _codec;
  final RecoverBullNostrAuthenticatedCipher _cipher;
  final Duration _timeout;

  const WebSocketWalletMetadataGraphRepository({
    required this._nostrIdentity,
    this._transport = const NostrRelayTransport(),
    this._keyDeriver = const WalletMetadataKeyDeriver(),
    this._codec = const WalletMetadataSnapshotCodec(),
    this._cipher = const RecoverBullNostrAuthenticatedCipher(),
    this._timeout = const Duration(seconds: 10),
  });

  @override
  @useResult
  Future<Result<WalletMetadataGraphScan, WalletMetadataBackupFailure>> fetch({
    required String xprvBase58,
    required String parentFingerprint,
    required List<WalletMetadataRelayUrl> relayUrls,
  }) async {
    final relays = relayUrls.toSet().toList(growable: false);
    if (relays.isEmpty) {
      return const Err(WalletMetadataBackupRelayFailure());
    }
    if (relays.length > WalletMetadataBackupLimits.maxRelays) {
      return const Err(WalletMetadataBackupResourceLimitFailure());
    }

    final WalletMetadataEncryptionKey encryptionKey;
    final String authorPublicKeyHex;
    try {
      encryptionKey = _keyDeriver.deriveEncryptionKey(
        xprvBase58: xprvBase58,
        expectedParentFingerprint: parentFingerprint,
      );
      authorPublicKeyHex = _nostrIdentity.deriveWalletMetadataPublicKeyFromXprv(
        xprvBase58,
      );
    } on WalletMetadataKeyDerivationException {
      return const Err(WalletMetadataBackupKeyFailure());
    } on Exception {
      return const Err(WalletMetadataBackupKeyFailure());
    }
    final normalizedFingerprint = parentFingerprint.trim().toLowerCase();
    final rootDTag = _keyDeriver.deriveRootDTag(encryptionKey);
    final rootFetches = await Future.wait(
      relays.indexed.map(
        (entry) => _fetchRootsFromRelay(
          relayUrl: entry.$2,
          relayIndex: entry.$1,
          authorPublicKeyHex: authorPublicKeyHex,
          rootDTag: rootDTag,
        ),
      ),
    );

    final observations = <WalletMetadataRelayRootObservation>[];
    final signedRootsById = <String, NostrSignedEvent>{};
    final rootRelaysById = <String, Set<WalletMetadataRelayUrl>>{};
    int? highestObservedRootCreatedAt;
    for (final fetch in rootFetches) {
      var authenticRootCount = 0;
      for (final relayEvent in fetch.events) {
        final signed = _targetedRootEvent(
          relayEvent,
          authorPublicKeyHex: authorPublicKeyHex,
          rootDTag: rootDTag,
        );
        if (signed == null) continue;
        authenticRootCount++;
        signedRootsById[signed.id] = signed;
        rootRelaysById.putIfAbsent(signed.id, () => {}).add(fetch.relayUrl);
        final highest = highestObservedRootCreatedAt;
        if (highest == null || signed.createdAt > highest) {
          highestObservedRootCreatedAt = signed.createdAt;
        }
      }
      observations.add(
        WalletMetadataRelayRootObservation(
          relayUrl: fetch.relayUrl,
          status: fetch.status,
          authenticRootCount: authenticRootCount,
        ),
      );
    }

    final failuresById = <String, WalletMetadataRootFailureObservation>{};
    final decodedRoots = <_DecodedRootCandidate>[];
    for (final signed in signedRootsById.values) {
      final mapped = _decodeRootCandidate(
        signed: signed,
        expectedAuthorPublicKeyHex: authorPublicKeyHex,
        expectedRootDTag: rootDTag,
        expectedParentFingerprint: normalizedFingerprint,
        encryptionKey: encryptionKey,
        sourceRelays: rootRelaysById[signed.id]!.toList(growable: false),
      );
      switch (mapped) {
        case _DecodedRootCandidate():
          decodedRoots.add(mapped);
        case _FailedRootCandidate(:final failure):
          failuresById[failure.rootEventId] = failure;
      }
    }
    decodedRoots.sort(_compareDecodedRootsNewestFirst);

    final completeHeads = <WalletMetadataRemoteHead>[];
    final candidatesToAttempt = decodedRoots.take(
      WalletMetadataBackupLimits.maxGraphCandidates,
    );
    for (final candidate in candidatesToAttempt) {
      final graph = await _fetchCompleteGraph(
        candidate: candidate,
        relays: relays,
        encryptionKey: encryptionKey,
        highestObservedRootCreatedAt: highestObservedRootCreatedAt!,
      );
      switch (graph) {
        case _CompleteGraph(:final head):
          completeHeads.add(head);
        case _FailedGraph(:final failure):
          failuresById[failure.rootEventId] = failure;
      }
      if (completeHeads.isNotEmpty) break;
    }
    if (completeHeads.isEmpty &&
        decodedRoots.length > WalletMetadataBackupLimits.maxGraphCandidates) {
      final firstUnattempted =
          decodedRoots[WalletMetadataBackupLimits.maxGraphCandidates];
      failuresById[firstUnattempted.event.id] =
          WalletMetadataRootFailureObservation(
            rootEventId: firstUnattempted.event.id,
            eventCreatedAt: firstUnattempted.event.createdAt,
            revision: firstUnattempted.root.revision,
            kind: WalletMetadataRootFailureKind.resourceLimit,
          );
    }

    return Ok(
      WalletMetadataGraphScan(
        relayObservations: observations,
        completeHeads: completeHeads,
        failures: failuresById.values.toList(growable: false),
        highestObservedRootCreatedAt: highestObservedRootCreatedAt,
      ),
    );
  }

  Future<_RelayRootFetch> _fetchRootsFromRelay({
    required WalletMetadataRelayUrl relayUrl,
    required int relayIndex,
    required String authorPublicKeyHex,
    required String rootDTag,
  }) async {
    final subscriptionId =
        'wm-root-${authorPublicKeyHex.substring(0, 12)}-$relayIndex';
    try {
      final outcome = await _transport.fetch(
        relayUri: relayUrl.uri,
        requestMessage: jsonEncode([
          'REQ',
          subscriptionId,
          {
            'authors': [authorPublicKeyHex],
            'kinds': [walletMetadataNostrEventKind],
            '#d': [rootDTag],
            'limit': WalletMetadataBackupLimits.maxRootCandidatesPerRelay,
          },
        ]),
        subscriptionId: subscriptionId,
        limit: WalletMetadataBackupLimits.maxRootCandidatesPerRelay,
        maxFrameBytes:
            WalletMetadataBackupLimits.maxEventFrameBytes +
            WalletMetadataBackupLimits.maxRelayResponseFrameAllowance,
        timeout: _timeout,
      );
      final status =
          !outcome.contactedRelay ||
              outcome.status == NostrRelayFetchStatus.unavailable
          ? WalletMetadataRelayRootQueryStatus.unavailable
          : outcome.status == NostrRelayFetchStatus.completed &&
                outcome.completedByEose
          ? WalletMetadataRelayRootQueryStatus.complete
          : WalletMetadataRelayRootQueryStatus.partial;
      return _RelayRootFetch(
        relayUrl: relayUrl,
        status: status,
        events: outcome.events,
      );
    } on Exception {
      return _RelayRootFetch(
        relayUrl: relayUrl,
        status: WalletMetadataRelayRootQueryStatus.unavailable,
        events: const [],
      );
    }
  }

  NostrSignedEvent? _targetedRootEvent(
    nostr.Event relayEvent, {
    required String authorPublicKeyHex,
    required String rootDTag,
  }) {
    try {
      final signed = const NostrSignedEventCodec().fromNostrEvent(relayEvent);
      final hasRootTag = signed.tags.any(
        (tag) => tag.length >= 2 && tag.first == 'd' && tag[1] == rootDTag,
      );
      if (signed.authorPublicKeyHex != authorPublicKeyHex ||
          signed.kind != walletMetadataNostrEventKind ||
          signed.createdAt > WalletMetadataBackupLimits.maxSignedInt64 ||
          !hasRootTag) {
        return null;
      }
      return signed;
    } on NostrEventException {
      return null;
    }
  }

  _RootCandidateOutcome _decodeRootCandidate({
    required NostrSignedEvent signed,
    required String expectedAuthorPublicKeyHex,
    required String expectedRootDTag,
    required String expectedParentFingerprint,
    required WalletMetadataEncryptionKey encryptionKey,
    required List<WalletMetadataRelayUrl> sourceRelays,
  }) {
    final event = _opaqueEvent(
      signed,
      expectedAuthorPublicKeyHex: expectedAuthorPublicKeyHex,
      expectedDTag: expectedRootDTag,
    );
    if (event == null) return _unreadableRoot(signed);

    final String plaintext;
    try {
      plaintext = _cipher.decrypt(
        ciphertext: NostrAuthenticatedCiphertext(event.encryptedContent),
        key: NostrAuthenticatedCipherKey(encryptionKey.hex),
      );
    } on NostrAuthenticatedCipherException {
      return _unreadableRoot(signed);
    }

    final WalletMetadataSnapshotRoot root;
    try {
      root = _codec.decodeRoot(plaintext);
    } on WalletMetadataBackupFormatException catch (error) {
      if (error.type ==
              WalletMetadataBackupFormatExceptionType
                  .unsupportedEnvelopeVersion &&
          error.envelopeVersion != null) {
        return _FailedRootCandidate(
          WalletMetadataRootFailureObservation(
            rootEventId: signed.id,
            eventCreatedAt: signed.createdAt,
            envelopeVersion: error.envelopeVersion,
            kind: WalletMetadataRootFailureKind.unsupportedEnvelope,
          ),
        );
      }
      return _FailedRootCandidate(
        WalletMetadataRootFailureObservation(
          rootEventId: signed.id,
          eventCreatedAt: signed.createdAt,
          kind:
              error.type ==
                  WalletMetadataBackupFormatExceptionType.resourceLimit
              ? WalletMetadataRootFailureKind.resourceLimit
              : WalletMetadataRootFailureKind.unreadableRoot,
        ),
      );
    }

    final chunkTags = root.chunks.map((chunk) => chunk.dTag).toSet();
    if (root.parentFingerprint != expectedParentFingerprint ||
        root.createdAt != event.createdAt ||
        chunkTags.length != root.chunks.length ||
        chunkTags.contains(expectedRootDTag)) {
      return _FailedRootCandidate(
        WalletMetadataRootFailureObservation(
          rootEventId: event.id,
          eventCreatedAt: event.createdAt,
          revision: root.revision,
          kind: WalletMetadataRootFailureKind.unreadableRoot,
        ),
      );
    }
    return _DecodedRootCandidate(
      event: event,
      root: root,
      plaintextBytes: utf8.encode(plaintext).length,
      sourceRelays: sourceRelays,
    );
  }

  _FailedRootCandidate _unreadableRoot(NostrSignedEvent event) {
    return _FailedRootCandidate(
      WalletMetadataRootFailureObservation(
        rootEventId: event.id,
        eventCreatedAt: event.createdAt,
        kind: WalletMetadataRootFailureKind.unreadableRoot,
      ),
    );
  }

  WalletMetadataNostrEvent? _opaqueEvent(
    NostrSignedEvent signed, {
    required String expectedAuthorPublicKeyHex,
    required String expectedDTag,
  }) {
    if (signed.authorPublicKeyHex != expectedAuthorPublicKeyHex ||
        signed.kind != walletMetadataNostrEventKind ||
        signed.tags.length != 1 ||
        signed.tags.single.length != 2 ||
        signed.tags.single.first != 'd' ||
        signed.tags.single[1] != expectedDTag ||
        utf8.encode(const NostrSignedEventCodec().serialize(signed)).length >
            WalletMetadataBackupLimits.maxEventFrameBytes) {
      return null;
    }
    try {
      final ciphertext = NostrAuthenticatedCiphertext(signed.content);
      if (ciphertext.value != signed.content) return null;
    } on NostrAuthenticatedCipherException {
      return null;
    }
    return WalletMetadataNostrEvent(signed);
  }

  Future<_GraphOutcome> _fetchCompleteGraph({
    required _DecodedRootCandidate candidate,
    required List<WalletMetadataRelayUrl> relays,
    required WalletMetadataEncryptionKey encryptionKey,
    required int highestObservedRootCreatedAt,
  }) async {
    if (candidate.root.chunks.isEmpty) {
      final records = candidate.root.records;
      try {
        _codec.validateRootRecords(root: candidate.root, records: records);
        WalletMetadataEncryptedSnapshot(
          plaintextRoot: candidate.root,
          rootEvent: candidate.event,
          chunks: const [],
        );
      } on WalletMetadataBackupFormatException catch (error) {
        return _failedGraphForFormat(candidate, error);
      } on ArgumentError {
        return _FailedGraph(
          WalletMetadataRootFailureObservation(
            rootEventId: candidate.event.id,
            eventCreatedAt: candidate.event.createdAt,
            revision: candidate.root.revision,
            kind: WalletMetadataRootFailureKind.unreadableRoot,
          ),
        );
      }
      return _CompleteGraph(
        WalletMetadataRemoteHead(
          rootEventId: candidate.event.id,
          rootEventCreatedAt: candidate.event.createdAt,
          highestObservedRootCreatedAt: highestObservedRootCreatedAt,
          canonicalContentHash: _codec.contentHash(
            records: records,
            sections: candidate.root.sections,
          ),
          root: candidate.root,
          records: records,
        ),
      );
    }

    final referencesById = {
      for (final reference in candidate.root.chunks)
        reference.eventId: reference,
    };
    final chunksById = <String, _DecodedChunk>{};
    final sourceRelays = candidate.sourceRelays.toSet();
    final orderedRelays = [
      ...candidate.sourceRelays,
      ...relays.where((relay) => !sourceRelays.contains(relay)),
    ];
    for (final entry in orderedRelays.indexed) {
      final fetch = await _fetchChunksFromRelay(
        candidate: candidate,
        relayUrl: entry.$2,
        relayIndex: entry.$1,
      );
      for (final relayEvent in fetch.events) {
        final decoded = _decodeChunkEvent(
          relayEvent: relayEvent,
          candidate: candidate,
          referencesById: referencesById,
          encryptionKey: encryptionKey,
        );
        if (decoded != null) chunksById[decoded.event.id] = decoded;
      }
      if (chunksById.length == candidate.root.chunks.length) break;
    }
    if (chunksById.length != candidate.root.chunks.length) {
      return _FailedGraph(
        WalletMetadataRootFailureObservation(
          rootEventId: candidate.event.id,
          eventCreatedAt: candidate.event.createdAt,
          revision: candidate.root.revision,
          kind: WalletMetadataRootFailureKind.incompleteGraph,
        ),
      );
    }

    final chunks = candidate.root.chunks
        .map((reference) => chunksById[reference.eventId]!)
        .toList(growable: false);
    final totalPlaintextBytes =
        candidate.plaintextBytes +
        chunks.fold<int>(0, (sum, chunk) => sum + chunk.plaintextBytes);
    if (totalPlaintextBytes >
        WalletMetadataBackupLimits.maxDecryptedSnapshotBytes) {
      return _FailedGraph(
        WalletMetadataRootFailureObservation(
          rootEventId: candidate.event.id,
          eventCreatedAt: candidate.event.createdAt,
          revision: candidate.root.revision,
          kind: WalletMetadataRootFailureKind.resourceLimit,
        ),
      );
    }
    final encryptedChunks = chunks
        .map(
          (chunk) => WalletMetadataEncryptedChunk(
            plaintext: chunk.chunk,
            event: chunk.event,
          ),
        )
        .toList(growable: false);
    WalletMetadataEncryptedSnapshot(
      plaintextRoot: candidate.root,
      rootEvent: candidate.event,
      chunks: encryptedChunks,
    );
    final records = chunks
        .expand((chunk) => chunk.chunk.records)
        .toList(growable: false);
    try {
      _codec.validateRootRecords(root: candidate.root, records: records);
    } on WalletMetadataBackupFormatException catch (error) {
      return _failedGraphForFormat(candidate, error);
    }
    return _CompleteGraph(
      WalletMetadataRemoteHead(
        rootEventId: candidate.event.id,
        rootEventCreatedAt: candidate.event.createdAt,
        highestObservedRootCreatedAt: highestObservedRootCreatedAt,
        canonicalContentHash: _codec.contentHash(
          records: records,
          sections: candidate.root.sections,
        ),
        root: candidate.root,
        records: records,
      ),
    );
  }

  Future<_RelayChunkFetch> _fetchChunksFromRelay({
    required _DecodedRootCandidate candidate,
    required WalletMetadataRelayUrl relayUrl,
    required int relayIndex,
  }) async {
    final subscriptionId =
        'wm-chunks-${candidate.event.id.substring(0, 12)}-$relayIndex';
    try {
      final outcome = await _transport.fetch(
        relayUri: relayUrl.uri,
        requestMessage: jsonEncode([
          'REQ',
          subscriptionId,
          {
            'ids': candidate.root.chunks
                .map((chunk) => chunk.eventId)
                .toList(growable: false),
            'authors': [candidate.event.authorPublicKeyHex],
            'kinds': [walletMetadataNostrEventKind],
            'limit': candidate.root.chunks.length,
          },
        ]),
        subscriptionId: subscriptionId,
        limit: candidate.root.chunks.length,
        maxFrameBytes:
            WalletMetadataBackupLimits.maxEventFrameBytes +
            WalletMetadataBackupLimits.maxRelayResponseFrameAllowance,
        timeout: _timeout,
      );
      return _RelayChunkFetch(events: outcome.events);
    } on Exception {
      return const _RelayChunkFetch(events: []);
    }
  }

  _DecodedChunk? _decodeChunkEvent({
    required nostr.Event relayEvent,
    required _DecodedRootCandidate candidate,
    required Map<String, WalletMetadataChunkReference> referencesById,
    required WalletMetadataEncryptionKey encryptionKey,
  }) {
    final NostrSignedEvent signed;
    try {
      signed = const NostrSignedEventCodec().fromNostrEvent(relayEvent);
    } on NostrEventException {
      return null;
    }
    final reference = referencesById[signed.id];
    if (reference == null) return null;
    final event = _opaqueEvent(
      signed,
      expectedAuthorPublicKeyHex: candidate.event.authorPublicKeyHex,
      expectedDTag: reference.dTag,
    );
    if (event == null ||
        event.createdAt != candidate.event.createdAt ||
        event.ciphertextHash != reference.ciphertextHash) {
      return null;
    }

    final String plaintext;
    try {
      plaintext = _cipher.decrypt(
        ciphertext: NostrAuthenticatedCiphertext(event.encryptedContent),
        key: NostrAuthenticatedCipherKey(encryptionKey.hex),
      );
    } on NostrAuthenticatedCipherException {
      return null;
    }
    final WalletMetadataSnapshotChunk chunk;
    try {
      chunk = _codec.decodeChunk(plaintext);
    } on WalletMetadataBackupFormatException {
      return null;
    }
    if (chunk.snapshotId != candidate.root.snapshotId ||
        chunk.index != reference.index ||
        chunk.chunkCount != candidate.root.chunks.length ||
        chunk.recordCount != reference.recordCount) {
      return null;
    }
    return _DecodedChunk(
      event: event,
      chunk: chunk,
      plaintextBytes: utf8.encode(plaintext).length,
    );
  }

  _FailedGraph _failedGraphForFormat(
    _DecodedRootCandidate candidate,
    WalletMetadataBackupFormatException error,
  ) {
    return _FailedGraph(
      WalletMetadataRootFailureObservation(
        rootEventId: candidate.event.id,
        eventCreatedAt: candidate.event.createdAt,
        revision: candidate.root.revision,
        kind:
            error.type == WalletMetadataBackupFormatExceptionType.resourceLimit
            ? WalletMetadataRootFailureKind.resourceLimit
            : WalletMetadataRootFailureKind.unreadableRoot,
      ),
    );
  }
}

final class _RelayRootFetch {
  final WalletMetadataRelayUrl relayUrl;
  final WalletMetadataRelayRootQueryStatus status;
  final List<nostr.Event> events;

  _RelayRootFetch({
    required this.relayUrl,
    required this.status,
    required List<nostr.Event> events,
  }) : events = List.unmodifiable(events);
}

final class _RelayChunkFetch {
  final List<nostr.Event> events;

  const _RelayChunkFetch({required this.events});
}

sealed class _RootCandidateOutcome {
  const _RootCandidateOutcome();
}

final class _DecodedRootCandidate extends _RootCandidateOutcome {
  final WalletMetadataNostrEvent event;
  final WalletMetadataSnapshotRoot root;
  final int plaintextBytes;
  final List<WalletMetadataRelayUrl> sourceRelays;

  _DecodedRootCandidate({
    required this.event,
    required this.root,
    required this.plaintextBytes,
    required List<WalletMetadataRelayUrl> sourceRelays,
  }) : sourceRelays = List.unmodifiable(sourceRelays);
}

final class _FailedRootCandidate extends _RootCandidateOutcome {
  final WalletMetadataRootFailureObservation failure;

  const _FailedRootCandidate(this.failure);
}

sealed class _GraphOutcome {
  const _GraphOutcome();
}

final class _CompleteGraph extends _GraphOutcome {
  final WalletMetadataRemoteHead head;

  const _CompleteGraph(this.head);
}

final class _FailedGraph extends _GraphOutcome {
  final WalletMetadataRootFailureObservation failure;

  const _FailedGraph(this.failure);
}

final class _DecodedChunk {
  final WalletMetadataNostrEvent event;
  final WalletMetadataSnapshotChunk chunk;
  final int plaintextBytes;

  const _DecodedChunk({
    required this.event,
    required this.chunk,
    required this.plaintextBytes,
  });
}

int _compareDecodedRootsNewestFirst(
  _DecodedRootCandidate left,
  _DecodedRootCandidate right,
) {
  final byRevision = right.root.revision.compareTo(left.root.revision);
  if (byRevision != 0) return byRevision;
  final byCreatedAt = right.event.createdAt.compareTo(left.event.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  return right.event.id.compareTo(left.event.id);
}
