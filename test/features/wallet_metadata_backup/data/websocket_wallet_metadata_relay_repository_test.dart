import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_relay_transport.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/websocket_wallet_metadata_relay_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;

void main() {
  test(
    'publishes chunks first, then root, then verifies exact events',
    () async {
      final snapshot = _snapshot();
      expect(snapshot.chunks.length, greaterThan(1));
      final transport = _FakeNostrRelayTransport(snapshot);
      final repository = WebSocketWalletMetadataRelayRepository(
        transport: transport,
      );
      final relay = WalletMetadataRelayUrl('wss://relay.example');

      final result = await repository.publishAndVerify(
        snapshot: snapshot,
        relayUrls: [relay, WalletMetadataRelayUrl('wss://relay.example/')],
      );

      final publication = _requireOk(result);
      expect(publication.acceptedReplicaCount, 1);
      expect(publication.verifiedReplicaCount, 1);
      expect(
        publication.relayOutcomes.single.status,
        WalletMetadataRelayReplicaStatus.verified,
      );
      expect(transport.calls.map((call) => call.operation), [
        ...List.filled(snapshot.chunks.length, 'publish'),
        'publish',
        'fetch',
      ]);
      expect(
        transport.calls
            .where((call) => call.operation == 'publish')
            .map((call) => call.eventId),
        [
          ...snapshot.chunks.map((chunk) => chunk.event.id),
          snapshot.rootEvent.id,
        ],
      );
      expect(transport.fetchCalls, hasLength(1));
      final fetch = transport.fetchCalls.single;
      expect(
        fetch.maxFrameBytes,
        WalletMetadataBackupLimits.maxEventFrameBytes + 512,
      );
      final request = jsonDecode(fetch.requestMessage) as List<Object?>;
      final filter = request[2]! as Map<String, Object?>;
      expect(filter['ids'], [
        snapshot.rootEvent.id,
        ...snapshot.chunks.map((chunk) => chunk.event.id),
      ]);
      expect(filter['authors'], [snapshot.rootEvent.authorPublicKeyHex]);
      expect(filter['kinds'], [30078]);
      expect(filter['limit'], snapshot.chunks.length + 1);
    },
  );

  test('does not publish a root after one chunk is rejected', () async {
    final snapshot = _snapshot();
    final transport = _FakeNostrRelayTransport(snapshot)
      ..publishStatuses[snapshot.chunks[1].event.id] =
          NostrRelayPublishStatus.rejected;
    final repository = WebSocketWalletMetadataRelayRepository(
      transport: transport,
    );

    final publication = _requireOk(
      await repository.publishAndVerify(
        snapshot: snapshot,
        relayUrls: [WalletMetadataRelayUrl('wss://relay.example')],
      ),
    );

    final outcome = publication.relayOutcomes.single;
    expect(outcome.status, WalletMetadataRelayReplicaStatus.chunksNotAccepted);
    expect(outcome.acceptedChunkCount, 1);
    expect(transport.calls.map((call) => call.eventId), [
      snapshot.chunks[0].event.id,
      snapshot.chunks[1].event.id,
    ]);
    expect(
      transport.calls.any((call) => call.eventId == snapshot.rootEvent.id),
      isFalse,
    );
    expect(transport.fetchCalls, isEmpty);
  });

  test('distinguishes root rejection from chunk rejection', () async {
    final snapshot = _snapshot();
    final transport = _FakeNostrRelayTransport(snapshot)
      ..publishStatuses[snapshot.rootEvent.id] =
          NostrRelayPublishStatus.rejected;
    final repository = WebSocketWalletMetadataRelayRepository(
      transport: transport,
    );

    final publication = _requireOk(
      await repository.publishAndVerify(
        snapshot: snapshot,
        relayUrls: [WalletMetadataRelayUrl('wss://relay.example')],
      ),
    );

    final outcome = publication.relayOutcomes.single;
    expect(outcome.status, WalletMetadataRelayReplicaStatus.rootNotAccepted);
    expect(outcome.acceptedChunkCount, snapshot.chunks.length);
    expect(publication.acceptedReplicaCount, 0);
    expect(transport.fetchCalls, isEmpty);
  });

  test(
    'keeps an accepted root retryable when exact read-back is incomplete',
    () async {
      final snapshot = _snapshot();
      final transport = _FakeNostrRelayTransport(snapshot)
        ..readBackEvents = _events(snapshot).skip(1).toList(growable: false);
      final repository = WebSocketWalletMetadataRelayRepository(
        transport: transport,
      );

      final publication = _requireOk(
        await repository.publishAndVerify(
          snapshot: snapshot,
          relayUrls: [WalletMetadataRelayUrl('wss://relay.example')],
        ),
      );

      expect(publication.acceptedReplicaCount, 1);
      expect(publication.verifiedReplicaCount, 0);
      expect(
        publication.relayOutcomes.single.status,
        WalletMetadataRelayReplicaStatus.acceptedUnverified,
      );
    },
  );

  test('isolates partial outcomes across relays', () async {
    final snapshot = _snapshot();
    final transport = _FakeNostrRelayTransport(snapshot)
      ..relayPublishStatuses['wss://root-rejected.example'] = {
        snapshot.rootEvent.id: NostrRelayPublishStatus.rejected,
      }
      ..relayPublishStatuses['wss://chunk-rejected.example'] = {
        snapshot.chunks.first.event.id: NostrRelayPublishStatus.rejected,
      };
    final repository = WebSocketWalletMetadataRelayRepository(
      transport: transport,
    );
    final relays = [
      WalletMetadataRelayUrl('wss://verified.example'),
      WalletMetadataRelayUrl('wss://root-rejected.example'),
      WalletMetadataRelayUrl('wss://chunk-rejected.example'),
    ];

    final publication = _requireOk(
      await repository.publishAndVerify(snapshot: snapshot, relayUrls: relays),
    );

    expect(publication.acceptedReplicaCount, 1);
    expect(publication.verifiedReplicaCount, 1);
    expect(publication.relayOutcomes.map((outcome) => outcome.status).toSet(), {
      WalletMetadataRelayReplicaStatus.verified,
      WalletMetadataRelayReplicaStatus.rootNotAccepted,
      WalletMetadataRelayReplicaStatus.chunksNotAccepted,
    });
    final chunkRejectedCalls = transport.calls.where(
      (call) => call.relayUri.toString() == 'wss://chunk-rejected.example',
    );
    expect(chunkRejectedCalls, hasLength(1));
    expect(chunkRejectedCalls.single.eventId, snapshot.chunks.first.event.id);
  });

  test(
    'publishes and verifies a fitting non-empty snapshot as one event',
    () async {
      final snapshot = _snapshot(
        records: [
          WalletMetadataRecord(
            type: 'labels.bip329',
            version: 1,
            scope: const {'kind': 'global'},
            recordId: 'label-inline',
            payload: const {'label': 'small private label'},
          ),
        ],
      );
      expect(snapshot.plaintextRoot.records, hasLength(1));
      expect(snapshot.chunks, isEmpty);
      final transport = _FakeNostrRelayTransport(snapshot);
      final repository = WebSocketWalletMetadataRelayRepository(
        transport: transport,
      );

      final publication = _requireOk(
        await repository.publishAndVerify(
          snapshot: snapshot,
          relayUrls: [WalletMetadataRelayUrl('wss://relay.example')],
        ),
      );

      expect(publication.verifiedReplicaCount, 1);
      expect(transport.calls.map((call) => call.operation), [
        'publish',
        'fetch',
      ]);
      final request =
          jsonDecode(transport.fetchCalls.single.requestMessage)
              as List<Object?>;
      final filter = request[2]! as Map<String, Object?>;
      expect(filter['ids'], [snapshot.rootEvent.id]);
      expect(filter['limit'], 1);
    },
  );

  test(
    'publishes and verifies an empty snapshot without chunk writes',
    () async {
      final snapshot = _snapshot(records: const []);
      expect(snapshot.chunks, isEmpty);
      final transport = _FakeNostrRelayTransport(snapshot);
      final repository = WebSocketWalletMetadataRelayRepository(
        transport: transport,
      );

      final publication = _requireOk(
        await repository.publishAndVerify(
          snapshot: snapshot,
          relayUrls: [WalletMetadataRelayUrl('wss://relay.example')],
        ),
      );

      expect(publication.verifiedReplicaCount, 1);
      expect(transport.calls.map((call) => call.operation), [
        'publish',
        'fetch',
      ]);
      expect(transport.calls.first.eventId, snapshot.rootEvent.id);
    },
  );

  test(
    'returns a typed failure without contacting an empty relay set',
    () async {
      final snapshot = _snapshot(records: const []);
      final transport = _FakeNostrRelayTransport(snapshot);
      final repository = WebSocketWalletMetadataRelayRepository(
        transport: transport,
      );

      final result = await repository.publishAndVerify(
        snapshot: snapshot,
        relayUrls: const [],
      );

      expect(
        result,
        isA<
          Err<WalletMetadataSnapshotPublication, WalletMetadataBackupFailure>
        >(),
      );
      expect(transport.calls, isEmpty);
    },
  );

  test('rejects an oversized relay set before opening sockets', () async {
    final snapshot = _snapshot(records: const []);
    final transport = _FakeNostrRelayTransport(snapshot);
    final repository = WebSocketWalletMetadataRelayRepository(
      transport: transport,
    );
    final relays = List.generate(
      WalletMetadataBackupLimits.maxRelays + 1,
      (index) => WalletMetadataRelayUrl('wss://relay-$index.example'),
    );

    final result = await repository.publishAndVerify(
      snapshot: snapshot,
      relayUrls: relays,
    );

    expect(
      result,
      isA<
        Err<WalletMetadataSnapshotPublication, WalletMetadataBackupFailure>
      >(),
    );
    expect(
      (result
              as Err<
                WalletMetadataSnapshotPublication,
                WalletMetadataBackupFailure
              >)
          .failure,
      isA<WalletMetadataBackupResourceLimitFailure>(),
    );
    expect(transport.calls, isEmpty);
  });
}

WalletMetadataEncryptedSnapshot _snapshot({
  List<WalletMetadataRecord>? records,
}) {
  final sourceRecords =
      records ??
      List.generate(
        4,
        (index) => WalletMetadataRecord(
          type: 'labels.bip329',
          version: 1,
          scope: const {'kind': 'global'},
          recordId: 'label-$index',
          payload: {'label': '${'x' * 1200}-$index'},
        ),
      );
  const codec = WalletMetadataSnapshotCodec();
  final sections = [
    WalletMetadataSection(
      type: 'labels.bip329',
      versions: const [1],
      recordCount: sourceRecords.length,
      recordsHash: codec.recordsHash(sourceRecords),
    ),
  ];
  var randomCounter = 0;
  final repository = WalletMetadataSnapshotRepositoryImpl(
    nostrIdentity: _nostrIdentity,
    maxFrameBytes: 3200,
    randomHex: (byteLength) {
      randomCounter++;
      return randomCounter
          .toRadixString(16)
          .padLeft(byteLength * 2, '0')
          .substring(0, byteLength * 2);
    },
  );
  final result = repository.build(
    xprvBase58: _masterXprv,
    parentFingerprint: _parentFingerprint,
    revision: 2,
    createdAt: 1784073600,
    records: sourceRecords,
    sections: sections,
  );
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'could not build test snapshot: ${failure.runtimeType}',
    ),
  };
}

List<nostr.Event> _events(WalletMetadataEncryptedSnapshot snapshot) {
  return [snapshot.rootEvent, ...snapshot.chunks.map((chunk) => chunk.event)]
      .map((event) {
        final message = nostr.Message.deserialize(
          event.serializedFrame,
        ).message;
        if (message is! nostr.Event) {
          throw TestFailure('expected an EVENT frame');
        }
        return message;
      })
      .toList(growable: false);
}

WalletMetadataSnapshotPublication _requireOk(
  Result<WalletMetadataSnapshotPublication, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}

final class _FakeNostrRelayTransport extends NostrRelayTransport {
  final WalletMetadataEncryptedSnapshot snapshot;
  final Map<String, NostrRelayPublishStatus> publishStatuses = {};
  final Map<String, Map<String, NostrRelayPublishStatus>> relayPublishStatuses =
      {};
  final List<_TransportCall> calls = [];
  final List<_FetchCall> fetchCalls = [];
  NostrRelayFetchStatus fetchStatus = NostrRelayFetchStatus.completed;
  List<nostr.Event>? readBackEvents;

  _FakeNostrRelayTransport(this.snapshot);

  @override
  Future<NostrRelayPublishOutcome> publish({
    required Uri relayUri,
    required String eventMessage,
    required String eventId,
    required Duration timeout,
  }) async {
    calls.add(
      _TransportCall(
        operation: 'publish',
        relayUri: relayUri,
        eventId: eventId,
      ),
    );
    final status =
        relayPublishStatuses[relayUri.toString()]?[eventId] ??
        publishStatuses[eventId] ??
        NostrRelayPublishStatus.accepted;
    return NostrRelayPublishOutcome(
      relayUri: relayUri,
      status: status,
      contactedRelay: status != NostrRelayPublishStatus.unavailable,
    );
  }

  @override
  Future<NostrRelayFetchOutcome> fetch({
    required Uri relayUri,
    required String requestMessage,
    required String subscriptionId,
    required int limit,
    required int maxFrameBytes,
    required Duration timeout,
  }) async {
    calls.add(
      _TransportCall(operation: 'fetch', relayUri: relayUri, eventId: null),
    );
    fetchCalls.add(
      _FetchCall(
        requestMessage: requestMessage,
        limit: limit,
        maxFrameBytes: maxFrameBytes,
      ),
    );
    return NostrRelayFetchOutcome(
      relayUri: relayUri,
      status: fetchStatus,
      contactedRelay: fetchStatus != NostrRelayFetchStatus.unavailable,
      completedByEose: fetchStatus == NostrRelayFetchStatus.completed,
      events: readBackEvents ?? _events(snapshot),
    );
  }
}

final class _TransportCall {
  final String operation;
  final Uri relayUri;
  final String? eventId;

  const _TransportCall({
    required this.operation,
    required this.relayUri,
    required this.eventId,
  });
}

final class _FetchCall {
  final String requestMessage;
  final int limit;
  final int maxFrameBytes;

  const _FetchCall({
    required this.requestMessage,
    required this.limit,
    required this.maxFrameBytes,
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
