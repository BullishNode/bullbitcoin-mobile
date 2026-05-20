import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_nostr_snapshot_store.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/application/services/bip139_wallet_manifest_codec.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:nostr/nostr.dart';

const walletManifestNostrKind = 30078;
const walletManifestNostrDTag = 'manifest';
const walletManifestNostrFetchLimit = 10;

class NostrWalletManifestSnapshotStore
    implements WalletManifestNostrSnapshotStore {
  final NostrRelayClient _relayClient;
  final Bip139WalletManifestCodec _codec;

  const NostrWalletManifestSnapshotStore({
    required NostrRelayClient relayClient,
    Bip139WalletManifestCodec codec = const Bip139WalletManifestCodec(),
  }) : _relayClient = relayClient,
       _codec = codec;

  @override
  Future<void> publish({
    required NostrKeychainHandle handle,
    required WalletManifestSnapshot snapshot,
  }) {
    return handle.withSecretKeyHex((secretKeyHex) async {
      try {
        final plaintext = _codec.encode(_publishableSnapshot(snapshot));
        final encrypted = await Encryption.encrypt(
          plaintext: plaintext,
          senderSecretKey: secretKeyHex,
          recipientPublicKey: handle.publicKeyHex,
        );
        final event = Event.from(
          kind: walletManifestNostrKind,
          tags: const [
            ['d', walletManifestNostrDTag],
          ],
          content: encrypted,
          secretKey: secretKeyHex,
        );

        await _relayClient.publish(
          event,
          confirmation: NostrPublishConfirmation.accepted,
        );
      } catch (e) {
        throw WalletManifestSnapshotPublishException(e);
      }
    });
  }

  @override
  Future<WalletManifestSnapshot?> fetchLatest({
    required NostrKeychainHandle handle,
  }) {
    return handle.withSecretKeyHex((secretKeyHex) async {
      final events = await _fetchEvents(handle);
      events.sort((a, b) {
        final createdAtOrder = b.createdAt.compareTo(a.createdAt);
        if (createdAtOrder != 0) return createdAtOrder;
        return b.id.compareTo(a.id);
      });

      for (final event in events) {
        if (!_matchesManifestEvent(event, handle.publicKeyHex)) continue;
        final snapshot = await _snapshotFromEvent(
          event: event,
          secretKeyHex: secretKeyHex,
        );
        if (snapshot != null) return snapshot;
      }

      return null;
    });
  }

  Future<List<Event>> _fetchEvents(NostrKeychainHandle handle) async {
    try {
      return await _relayClient.fetch(
        filter: Filter(
          authors: [handle.publicKeyHex],
          kinds: [walletManifestNostrKind],
          limit: walletManifestNostrFetchLimit,
        ),
        tagFilters: const {
          'd': [walletManifestNostrDTag],
        },
      );
    } catch (e) {
      throw WalletManifestSnapshotFetchException(e);
    }
  }

  Future<WalletManifestSnapshot?> _snapshotFromEvent({
    required Event event,
    required String secretKeyHex,
  }) async {
    try {
      final plaintext = await Encryption.decrypt(
        payload: event.content,
        recipientSecretKey: secretKeyHex,
        senderPublicKey: event.pubkey,
      );
      return _codec.decode(plaintext, fallbackCreatedAt: event.createdAt);
    } catch (_) {
      return null;
    }
  }

  bool _matchesManifestEvent(Event event, String expectedAuthor) {
    return event.kind == walletManifestNostrKind &&
        event.pubkey == expectedAuthor &&
        event.tags.any(
          (tag) =>
              tag.length >= 2 &&
              tag[0] == 'd' &&
              tag[1] == walletManifestNostrDTag,
        );
  }

  WalletManifestSnapshot _publishableSnapshot(WalletManifestSnapshot snapshot) {
    return WalletManifestSnapshot(
      createdAt: snapshot.createdAt,
      accounts: [
        for (final account in snapshot.accounts) account.withoutDescriptors(),
      ],
    );
  }
}
