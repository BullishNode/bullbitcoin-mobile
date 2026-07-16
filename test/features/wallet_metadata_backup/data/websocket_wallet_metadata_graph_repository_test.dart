import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_relay_transport.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_key_deriver.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_nostr_event_encoder.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_safe_head_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/websocket_wallet_metadata_graph_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_graph_scan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_nostr_event.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;

void main() {
  test('recovers an inline root without requesting chunks', () async {
    final snapshot = _snapshot(revision: 2, createdAt: 900);
    expect(snapshot.chunks, isEmpty);
    expect(snapshot.plaintextRoot.records, hasLength(1));
    final transport = _FakeGraphTransport()
      ..rootEvents['wss://relay.example'] = [_event(snapshot.rootEvent)];

    final scan = _requireOk(
      await _fetch(_repository(transport), [
        WalletMetadataRelayUrl('wss://relay.example'),
      ]),
    );

    expect(scan.bestCompleteHead?.records.single.recordId, 'label-2');
    expect(
      transport.requests.where((request) => !request.isRootRequest),
      isEmpty,
    );
  });

  test('assembles an authenticated graph across different relays', () async {
    final snapshot = _snapshot(revision: 3, createdAt: 1000, forceChunks: true);
    final transport = _FakeGraphTransport()
      ..rootEvents['wss://roots.example'] = [_event(snapshot.rootEvent)]
      ..chunkEvents['wss://chunks.example'] = snapshot.chunks
          .map((chunk) => _event(chunk.event))
          .toList(growable: false);
    final repository = _repository(transport);
    final relays = [
      WalletMetadataRelayUrl('wss://roots.example'),
      WalletMetadataRelayUrl('wss://chunks.example'),
    ];

    final scan = _requireOk(await _fetch(repository, relays));

    expect(scan.allRootQueriesComplete, isTrue);
    expect(scan.completeHeads, hasLength(1));
    expect(scan.failures, isEmpty);
    expect(scan.bestCompleteHead?.root.revision, 3);
    expect(scan.bestCompleteHead?.records.single.recordId, 'label-3');
    expect(
      transport.requests.where((request) => request.isRootRequest),
      hasLength(2),
    );
    expect(
      transport.requests.where((request) => !request.isRootRequest),
      hasLength(2),
    );

    final safe = _requireSafeOk(
      await WalletMetadataSafeHeadRepositoryImpl(
        graphRepository: repository,
        clock: const _FixedClock(1100),
      ).fetchForPublication(
        xprvBase58: _masterXprv,
        parentFingerprint: _parentFingerprint,
        relayUrls: relays,
      ),
    );
    expect(safe, isA<WalletMetadataSafeHeadCompatible>());
  });

  test('prioritizes a root source and stops after a complete graph', () async {
    final snapshot = _snapshot(revision: 3, createdAt: 1000, forceChunks: true);
    final transport = _FakeGraphTransport()
      ..rootEvents['wss://source.example'] = [_event(snapshot.rootEvent)]
      ..chunkEvents['wss://source.example'] = snapshot.chunks
          .map((chunk) => _event(chunk.event))
          .toList(growable: false);
    final relays = [
      WalletMetadataRelayUrl('wss://empty.example'),
      WalletMetadataRelayUrl('wss://source.example'),
      WalletMetadataRelayUrl('wss://unused.example'),
    ];

    final scan = _requireOk(await _fetch(_repository(transport), relays));

    expect(scan.completeHeads, hasLength(1));
    final chunkRequests = transport.requests
        .where((request) => !request.isRootRequest)
        .toList(growable: false);
    expect(chunkRequests, hasLength(1));
    expect(chunkRequests.single.relayUri.toString(), 'wss://source.example');
  });

  test(
    'falls back to an older complete graph but blocks safe publication',
    () async {
      final older = _snapshot(revision: 4, createdAt: 1000, forceChunks: true);
      final newer = _snapshot(revision: 5, createdAt: 1100, forceChunks: true);
      final transport = _FakeGraphTransport()
        ..rootEvents['wss://relay.example'] = [
          _event(older.rootEvent),
          _event(newer.rootEvent),
        ]
        ..chunkEvents['wss://relay.example'] = older.chunks
            .map((chunk) => _event(chunk.event))
            .toList(growable: false);
      final repository = _repository(transport);
      final relays = [WalletMetadataRelayUrl('wss://relay.example')];

      final scan = _requireOk(await _fetch(repository, relays));

      expect(scan.bestCompleteHead?.root.revision, 4);
      expect(scan.failures, hasLength(1));
      expect(
        scan.failures.single.kind,
        WalletMetadataRootFailureKind.incompleteGraph,
      );
      expect(scan.failures.single.revision, 5);
      expect(scan.blockersNewerThan(scan.bestCompleteHead!), hasLength(1));

      final safe = _requireSafeOk(
        await WalletMetadataSafeHeadRepositoryImpl(
          graphRepository: repository,
        ).fetchForPublication(
          xprvBase58: _masterXprv,
          parentFingerprint: _parentFingerprint,
          relayUrls: relays,
        ),
      );
      expect(safe, isA<WalletMetadataSafeHeadIncomplete>());
    },
  );

  test('reports a newer authenticated unsupported envelope', () async {
    final older = _snapshot(revision: 8, createdAt: 1000);
    final unsupported = _opaqueRootEvent(
      plaintext: '{"envelopeVersion":2}',
      createdAt: 1200,
    );
    final transport = _FakeGraphTransport()
      ..rootEvents['wss://relay.example'] = [
        _event(older.rootEvent),
        _event(unsupported),
      ]
      ..chunkEvents['wss://relay.example'] = older.chunks
          .map((chunk) => _event(chunk.event))
          .toList(growable: false);
    final repository = _repository(transport);
    final relays = [WalletMetadataRelayUrl('wss://relay.example')];

    final scan = _requireOk(await _fetch(repository, relays));

    expect(scan.bestCompleteHead?.root.revision, 8);
    expect(
      scan.failures.single.kind,
      WalletMetadataRootFailureKind.unsupportedEnvelope,
    );
    expect(scan.failures.single.envelopeVersion, 2);

    final safe = _requireSafeOk(
      await WalletMetadataSafeHeadRepositoryImpl(
        graphRepository: repository,
        clock: const _FixedClock(1300),
      ).fetchForPublication(
        xprvBase58: _masterXprv,
        parentFingerprint: _parentFingerprint,
        relayUrls: relays,
      ),
    );
    expect(safe, isA<WalletMetadataSafeHeadUnsupported>());
    final blocked = safe as WalletMetadataSafeHeadUnsupported;
    expect(blocked.unsupported.rootEventId, unsupported.id);
    expect(blocked.unsupported.envelopeVersion, 2);
    expect(blocked.unsupported.observedAt, 1300);
  });

  test(
    'an older malformed root does not outrank a newer complete revision',
    () async {
      final complete = _snapshot(revision: 6, createdAt: 1200);
      final malformed = _opaqueRootEvent(
        plaintext: '{"envelopeVersion":1}',
        createdAt: 900,
      );
      final transport = _FakeGraphTransport()
        ..rootEvents['wss://relay.example'] = [
          _event(malformed),
          _event(complete.rootEvent),
        ]
        ..chunkEvents['wss://relay.example'] = complete.chunks
            .map((chunk) => _event(chunk.event))
            .toList(growable: false);
      final repository = _repository(transport);
      final relays = [WalletMetadataRelayUrl('wss://relay.example')];

      final scan = _requireOk(await _fetch(repository, relays));

      expect(
        scan.failures.single.kind,
        WalletMetadataRootFailureKind.unreadableRoot,
      );
      expect(scan.blockersNewerThan(scan.bestCompleteHead!), isEmpty);
      final safe = _requireSafeOk(
        await WalletMetadataSafeHeadRepositoryImpl(
          graphRepository: repository,
        ).fetchForPublication(
          xprvBase58: _masterXprv,
          parentFingerprint: _parentFingerprint,
          relayUrls: relays,
        ),
      );
      expect(safe, isA<WalletMetadataSafeHeadCompatible>());
    },
  );

  test('a complete empty head wins over an older populated snapshot', () async {
    final older = _snapshot(revision: 1, createdAt: 900);
    final empty = _snapshot(revision: 2, createdAt: 1000, records: const []);
    final transport = _FakeGraphTransport()
      ..rootEvents['wss://relay.example'] = [
        _event(older.rootEvent),
        _event(empty.rootEvent),
      ]
      ..chunkEvents['wss://relay.example'] = older.chunks
          .map((chunk) => _event(chunk.event))
          .toList(growable: false);

    final scan = _requireOk(
      await _fetch(_repository(transport), [
        WalletMetadataRelayUrl('wss://relay.example'),
      ]),
    );

    expect(scan.bestCompleteHead?.root.revision, 2);
    expect(scan.bestCompleteHead?.records, isEmpty);
    expect(
      transport.requests.where((request) => !request.isRootRequest),
      isEmpty,
    );
  });

  test('rejects a decryptable root with the wrong owner fingerprint', () async {
    final source = _snapshot(revision: 3, createdAt: 1000);
    final wrongOwnerRoot = WalletMetadataSnapshotRoot(
      parentFingerprint: 'ffffffff',
      snapshotId: source.plaintextRoot.snapshotId,
      revision: source.plaintextRoot.revision,
      createdAt: source.plaintextRoot.createdAt,
      recordsHash: source.plaintextRoot.recordsHash,
      recordCount: source.plaintextRoot.recordCount,
      sections: source.plaintextRoot.sections,
      records: source.plaintextRoot.records,
      chunks: source.plaintextRoot.chunks,
    );
    final event = _opaqueRootEvent(
      plaintext: const WalletMetadataSnapshotCodec().encodeRoot(wrongOwnerRoot),
      createdAt: 1000,
    );
    final transport = _FakeGraphTransport()
      ..rootEvents['wss://relay.example'] = [_event(event)];

    final scan = _requireOk(
      await _fetch(_repository(transport), [
        WalletMetadataRelayUrl('wss://relay.example'),
      ]),
    );

    expect(scan.completeHeads, isEmpty);
    expect(scan.failures.single.revision, 3);
    expect(
      scan.failures.single.kind,
      WalletMetadataRootFailureKind.unreadableRoot,
    );
  });

  test('rejects a complete graph whose root records hash is false', () async {
    final source = _snapshot(revision: 3, createdAt: 1000);
    final falseRoot = WalletMetadataSnapshotRoot(
      parentFingerprint: source.plaintextRoot.parentFingerprint,
      snapshotId: source.plaintextRoot.snapshotId,
      revision: source.plaintextRoot.revision,
      createdAt: source.plaintextRoot.createdAt,
      recordsHash: 'f' * 64,
      recordCount: source.plaintextRoot.recordCount,
      sections: source.plaintextRoot.sections,
      records: source.plaintextRoot.records,
      chunks: source.plaintextRoot.chunks,
    );
    final falseRootEvent = _opaqueRootEvent(
      plaintext: const WalletMetadataSnapshotCodec().encodeRoot(falseRoot),
      createdAt: 1000,
    );
    final transport = _FakeGraphTransport()
      ..rootEvents['wss://relay.example'] = [_event(falseRootEvent)]
      ..chunkEvents['wss://relay.example'] = source.chunks
          .map((chunk) => _event(chunk.event))
          .toList(growable: false);

    final scan = _requireOk(
      await _fetch(_repository(transport), [
        WalletMetadataRelayUrl('wss://relay.example'),
      ]),
    );

    expect(scan.completeHeads, isEmpty);
    expect(
      scan.failures.single.kind,
      WalletMetadataRootFailureKind.unreadableRoot,
    );
  });

  test('safe publication requires EOSE from every root query', () async {
    final snapshot = _snapshot(revision: 3, createdAt: 1000);
    final transport = _FakeGraphTransport()
      ..rootEvents['wss://relay.example'] = [_event(snapshot.rootEvent)]
      ..chunkEvents['wss://relay.example'] = snapshot.chunks
          .map((chunk) => _event(chunk.event))
          .toList(growable: false)
      ..rootCompletedByEose['wss://relay.example'] = false;
    final repository = _repository(transport);
    final relays = [WalletMetadataRelayUrl('wss://relay.example')];

    final scan = _requireOk(await _fetch(repository, relays));
    expect(scan.bestCompleteHead, isNotNull);
    expect(scan.allRootQueriesComplete, isFalse);

    final safe = _requireSafeOk(
      await WalletMetadataSafeHeadRepositoryImpl(
        graphRepository: repository,
      ).fetchForPublication(
        xprvBase58: _masterXprv,
        parentFingerprint: _parentFingerprint,
        relayUrls: relays,
      ),
    );
    expect(safe, isA<WalletMetadataSafeHeadUnavailable>());
  });

  test('distinguishes complete absence from relay unavailability', () async {
    final completeTransport = _FakeGraphTransport();
    final unavailableTransport = _FakeGraphTransport()
      ..rootStatuses['wss://relay.example'] = NostrRelayFetchStatus.unavailable;
    final relays = [WalletMetadataRelayUrl('wss://relay.example')];

    final absent = _requireSafeOk(
      await WalletMetadataSafeHeadRepositoryImpl(
        graphRepository: _repository(completeTransport),
      ).fetchForPublication(
        xprvBase58: _masterXprv,
        parentFingerprint: _parentFingerprint,
        relayUrls: relays,
      ),
    );
    final unavailable = _requireSafeOk(
      await WalletMetadataSafeHeadRepositoryImpl(
        graphRepository: _repository(unavailableTransport),
      ).fetchForPublication(
        xprvBase58: _masterXprv,
        parentFingerprint: _parentFingerprint,
        relayUrls: relays,
      ),
    );

    expect(absent, isA<WalletMetadataSafeHeadNoSnapshot>());
    expect(unavailable, isA<WalletMetadataSafeHeadUnavailable>());
  });

  test('fails key validation before any relay query', () async {
    final transport = _FakeGraphTransport();

    final result = await _repository(transport).fetch(
      xprvBase58: _masterXprv,
      parentFingerprint: 'ffffffff',
      relayUrls: [WalletMetadataRelayUrl('wss://relay.example')],
    );

    expect(_requireFailure(result), isA<WalletMetadataBackupKeyFailure>());
    expect(transport.requests, isEmpty);
  });
}

WebSocketWalletMetadataGraphRepository _repository(
  NostrRelayTransport transport,
) {
  return WebSocketWalletMetadataGraphRepository(
    nostrIdentity: _nostrIdentity,
    transport: transport,
  );
}

Future<Result<WalletMetadataGraphScan, WalletMetadataBackupFailure>> _fetch(
  WebSocketWalletMetadataGraphRepository repository,
  List<WalletMetadataRelayUrl> relays,
) {
  return repository.fetch(
    xprvBase58: _masterXprv,
    parentFingerprint: _parentFingerprint,
    relayUrls: relays,
  );
}

WalletMetadataEncryptedSnapshot _snapshot({
  required int revision,
  required int createdAt,
  List<WalletMetadataRecord>? records,
  bool forceChunks = false,
}) {
  final sourceRecords =
      records ??
      [
        WalletMetadataRecord(
          type: 'labels.bip329',
          version: 1,
          scope: const {'kind': 'global'},
          recordId: 'label-$revision',
          payload: {
            'type': 'tx',
            'ref': revision.toRadixString(16).padLeft(64, '0'),
            'label': 'label $revision${forceChunks ? ' ${'x' * 2000}' : ''}',
          },
        ),
      ];
  const codec = WalletMetadataSnapshotCodec();
  final sections = [
    WalletMetadataSection(
      type: 'labels.bip329',
      versions: const [1],
      recordCount: sourceRecords.length,
      recordsHash: codec.recordsHash(sourceRecords),
    ),
  ];
  var counter = 0;
  final repository = WalletMetadataSnapshotRepositoryImpl(
    nostrIdentity: _nostrIdentity,
    maxFrameBytes: forceChunks
        ? _chunkFrameBytes(sourceRecords, createdAt: createdAt)
        : 131000,
    randomHex: (byteLength) {
      counter++;
      final seed = (revision * 1000 + counter).toRadixString(16);
      return seed.padLeft(byteLength * 2, '0').substring(0, byteLength * 2);
    },
  );
  final result = repository.build(
    xprvBase58: _masterXprv,
    parentFingerprint: _parentFingerprint,
    revision: revision,
    createdAt: createdAt,
    records: sourceRecords,
    sections: sections,
  );
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'could not build snapshot: ${failure.runtimeType}',
    ),
  };
}

int _chunkFrameBytes(
  List<WalletMetadataRecord> records, {
  required int createdAt,
}) {
  const codec = WalletMetadataSnapshotCodec();
  const keyDeriver = WalletMetadataKeyDeriver();
  final encryptionKey = keyDeriver.deriveEncryptionKey(
    xprvBase58: _masterXprv,
    expectedParentFingerprint: _parentFingerprint,
  );
  final chunk = WalletMetadataSnapshotChunk(
    snapshotId: 'a' * 32,
    index: 0,
    chunkCount: 1,
    recordCount: records.length,
    records: records,
  );
  return const WalletMetadataNostrEventEncoder()
      .encode(
        plaintext: codec.encodeChunk(chunk),
        dTag: 'b' * 64,
        createdAt: createdAt,
        encryptionKey: encryptionKey,
        signer: _nostrIdentity.deriveWalletMetadataSignerFromXprv(_masterXprv),
      )
      .frameByteLength;
}

WalletMetadataNostrEvent _opaqueRootEvent({
  required String plaintext,
  required int createdAt,
}) {
  const keyDeriver = WalletMetadataKeyDeriver();
  final encryptionKey = keyDeriver.deriveEncryptionKey(
    xprvBase58: _masterXprv,
    expectedParentFingerprint: _parentFingerprint,
  );
  return const WalletMetadataNostrEventEncoder().encode(
    plaintext: plaintext,
    dTag: keyDeriver.deriveRootDTag(encryptionKey),
    createdAt: createdAt,
    encryptionKey: encryptionKey,
    signer: _nostrIdentity.deriveWalletMetadataSignerFromXprv(_masterXprv),
  );
}

nostr.Event _event(WalletMetadataNostrEvent event) {
  final parsed = nostr.Message.deserialize(event.serializedFrame).message;
  if (parsed is! nostr.Event) throw TestFailure('expected EVENT frame');
  return parsed;
}

WalletMetadataGraphScan _requireOk(
  Result<WalletMetadataGraphScan, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}

WalletMetadataBackupFailure _requireFailure(
  Result<WalletMetadataGraphScan, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok() => throw TestFailure('expected failure'),
    Err(:final failure) => failure,
  };
}

WalletMetadataSafeHeadResult _requireSafeOk(
  Result<WalletMetadataSafeHeadResult, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected safe head, got ${failure.runtimeType}',
    ),
  };
}

final class _FakeGraphTransport extends NostrRelayTransport {
  final Map<String, List<nostr.Event>> rootEvents = {};
  final Map<String, List<nostr.Event>> chunkEvents = {};
  final Map<String, NostrRelayFetchStatus> rootStatuses = {};
  final Map<String, bool> rootCompletedByEose = {};
  final List<_FetchRequest> requests = [];

  @override
  Future<NostrRelayFetchOutcome> fetch({
    required Uri relayUri,
    required String requestMessage,
    required String subscriptionId,
    required int limit,
    required int maxFrameBytes,
    required Duration timeout,
  }) async {
    final decoded = jsonDecode(requestMessage) as List<Object?>;
    final filter = decoded[2]! as Map<String, Object?>;
    final isRootRequest = filter.containsKey('#d');
    requests.add(
      _FetchRequest(
        relayUri: relayUri,
        isRootRequest: isRootRequest,
        filter: filter,
      ),
    );
    final relay = relayUri.toString();
    final status = isRootRequest
        ? rootStatuses[relay] ?? NostrRelayFetchStatus.completed
        : NostrRelayFetchStatus.completed;
    final availableEvents = isRootRequest
        ? rootEvents[relay] ?? const []
        : chunkEvents[relay] ?? const [];
    final ids = (filter['ids'] as List<Object?>?)?.cast<String>().toSet();
    final events = ids == null
        ? availableEvents
        : availableEvents
              .where((event) => ids.contains(event.id))
              .toList(growable: false);
    return NostrRelayFetchOutcome(
      relayUri: relayUri,
      status: status,
      contactedRelay: status != NostrRelayFetchStatus.unavailable,
      completedByEose: isRootRequest
          ? rootCompletedByEose[relay] ??
                status == NostrRelayFetchStatus.completed
          : true,
      events: events,
    );
  }
}

final class _FetchRequest {
  final Uri relayUri;
  final bool isRootRequest;
  final Map<String, Object?> filter;

  const _FetchRequest({
    required this.relayUri,
    required this.isRootRequest,
    required this.filter,
  });
}

final class _FixedClock implements Clock {
  final int seconds;

  const _FixedClock(this.seconds);

  @override
  DateTime nowUtc() =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

const _nostrIdentity = NostrIdentityFacade(
  deriveHandle: DeriveNostrIdentityHandleUsecase(
    registry: Bip85RegistryFacade(),
  ),
);
const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
const _parentFingerprint = '627ef3a6';
