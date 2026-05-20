import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/application/services/bip139_wallet_manifest_codec.dart';
import 'package:bb_mobile/features/wallet_manifest/interface_adapters/nostr_wallet_manifest_snapshot_store.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart';

class _FakeRelayClient extends NostrRelayClient {
  _FakeRelayClient({
    this.publishError,
    this.fetchError,
    this.events = const [],
  });

  final NostrPublishFailedException? publishError;
  final NostrFetchFailedException? fetchError;
  final List<Event> events;

  Event? published;
  Filter? fetchedFilter;
  Map<String, List<String>>? fetchedTagFilters;
  NostrPublishConfirmation? publishConfirmation;

  @override
  Future<void> publish(
    Event event, {
    NostrPublishConfirmation confirmation = NostrPublishConfirmation.sent,
  }) async {
    final error = publishError;
    if (error != null) throw error;
    published = event;
    publishConfirmation = confirmation;
  }

  @override
  Future<List<Event>> fetch({
    required Filter filter,
    Map<String, List<String>> tagFilters = const {},
  }) async {
    final error = fetchError;
    if (error != null) throw error;
    fetchedFilter = filter;
    fetchedTagFilters = tagFilters;
    return events;
  }
}

void main() {
  const secretKeyHex =
      '0000000000000000000000000000000000000000000000000000000000000001';
  final handle = NostrKeychainHandle.fromSecretKeyHex(secretKeyHex);
  const codec = Bip139WalletManifestCodec();

  test(
    'publishes encrypted manifest snapshots as addressable events',
    () async {
      final relay = _FakeRelayClient();
      final store = NostrWalletManifestSnapshotStore(relayClient: relay);

      await store.publish(handle: handle, snapshot: _snapshot());

      final event = relay.published;
      expect(event, isNotNull);
      expect(event!.kind, walletManifestNostrKind);
      expect(event.pubkey, handle.publicKeyHex);
      expect(event.tags, [
        ['d', walletManifestNostrDTag],
      ]);
      expect(event.content, isNot(contains('Payment Page')));
      expect(relay.publishConfirmation, NostrPublishConfirmation.accepted);
      final decoded = codec.decode(
        await _decryptContent(event, secretKeyHex),
        fallbackCreatedAt: event.createdAt,
      );
      expect(decoded.accounts.single.name, 'Payment Page-LBTC');
      expect(decoded.accounts.single.descriptor, isNull);
      expect(decoded.accounts.single.changeDescriptor, isNull);
    },
  );

  test(
    'fetches newest valid encrypted snapshot by author kind and d tag',
    () async {
      final oldValid = await _event(
        secretKeyHex: secretKeyHex,
        createdAt: 100,
        snapshot: _snapshot(createdAt: 100, name: 'old'),
      );
      final newestInvalid = Event.from(
        createdAt: 300,
        kind: walletManifestNostrKind,
        tags: const [
          ['d', walletManifestNostrDTag],
        ],
        content: 'not encrypted',
        secretKey: secretKeyHex,
      );
      final newestValid = await _event(
        secretKeyHex: secretKeyHex,
        createdAt: 200,
        snapshot: _snapshot(createdAt: 200, name: 'new'),
      );
      final relay = _FakeRelayClient(
        events: [oldValid, newestInvalid, newestValid],
      );
      final store = NostrWalletManifestSnapshotStore(relayClient: relay);

      final fetched = await store.fetchLatest(handle: handle);

      expect(fetched, isNotNull);
      expect(fetched!.createdAt, 200);
      expect(fetched.accounts.single.name, 'new');
      final filter = relay.fetchedFilter!;
      expect(filter.authors, [handle.publicKeyHex]);
      expect(filter.kinds, [walletManifestNostrKind]);
      expect(filter.limit, walletManifestNostrFetchLimit);
      expect(relay.fetchedTagFilters, {
        'd': [walletManifestNostrDTag],
      });
    },
  );

  test('returns null when no candidate decrypts to a valid manifest', () async {
    final relay = _FakeRelayClient(
      events: [
        Event.from(
          createdAt: 300,
          kind: walletManifestNostrKind,
          tags: const [
            ['d', walletManifestNostrDTag],
          ],
          content: 'not encrypted',
          secretKey: secretKeyHex,
        ),
      ],
    );
    final store = NostrWalletManifestSnapshotStore(relayClient: relay);

    final fetched = await store.fetchLatest(handle: handle);

    expect(fetched, isNull);
  });

  test('maps relay failures to wallet manifest errors', () async {
    final publishStore = NostrWalletManifestSnapshotStore(
      relayClient: _FakeRelayClient(
        publishError: NostrPublishFailedException('no relay accepted'),
      ),
    );
    await expectLater(
      publishStore.publish(handle: handle, snapshot: _snapshot()),
      throwsA(isA<WalletManifestSnapshotPublishException>()),
    );

    final fetchStore = NostrWalletManifestSnapshotStore(
      relayClient: _FakeRelayClient(
        fetchError: NostrFetchFailedException('no relay answered'),
      ),
    );
    await expectLater(
      fetchStore.fetchLatest(handle: handle),
      throwsA(isA<WalletManifestSnapshotFetchException>()),
    );
  });
}

WalletManifestSnapshot _snapshot({
  int createdAt = 123,
  String name = 'Payment Page-LBTC',
}) {
  return WalletManifestSnapshot(
    createdAt: createdAt,
    accounts: [
      WalletManifestAccount(
        rootFingerprint: '73c5da0a',
        bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 76),
        network: WalletManifestNetwork.liquid,
        name: name,
        descriptor: 'ct(slip77(...),elwpkh(xpub/0/*))',
        changeDescriptor: 'ct(slip77(...),elwpkh(xpub/1/*))',
        timestamp: createdAt,
      ),
    ],
  );
}

Future<Event> _event({
  required String secretKeyHex,
  required int createdAt,
  required WalletManifestSnapshot snapshot,
}) async {
  const codec = Bip139WalletManifestCodec();
  final plaintext = codec.encode(snapshot);
  final keys = Keys(secretKeyHex);
  final encrypted = await Encryption.encrypt(
    plaintext: plaintext,
    senderSecretKey: secretKeyHex,
    recipientPublicKey: keys.public,
  );
  return Event.from(
    createdAt: createdAt,
    kind: walletManifestNostrKind,
    tags: const [
      ['d', walletManifestNostrDTag],
    ],
    content: encrypted,
    secretKey: secretKeyHex,
  );
}

Future<String> _decryptContent(Event event, String secretKeyHex) {
  return Encryption.decrypt(
    payload: event.content,
    recipientSecretKey: secretKeyHex,
    senderPublicKey: event.pubkey,
  );
}
