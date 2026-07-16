import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_relay_transport.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';

class WebSocketKeychainManifestNostrRelayRepository
    implements KeychainManifestNostrRelayRepository {
  static const _fetchLimit = 20;
  static const _maxEventFrameBytes = 256 * 1024;

  final NostrRelayTransport _transport;
  final KeychainManifestNostrSignedEventCodec _eventCodec;
  final Duration _timeout;

  const WebSocketKeychainManifestNostrRelayRepository({
    NostrRelayTransport transport = const NostrRelayTransport(),
    KeychainManifestNostrSignedEventCodec eventCodec =
        const KeychainManifestNostrSignedEventCodec(),
    Duration timeout = const Duration(seconds: 10),
  }) : this._(transport, eventCodec, timeout);

  const WebSocketKeychainManifestNostrRelayRepository._(
    this._transport,
    this._eventCodec,
    this._timeout,
  );

  @override
  Future<bool> publish({
    required KeychainManifestNostrSignedEvent event,
    required List<KeychainManifestNostrRelayUrl> relayUrls,
  }) async {
    final uniqueRelayUrls = relayUrls.toSet().toList(growable: false);
    final eventMessage = _eventCodec.serialize(event);
    final outcomes = await Future.wait(
      uniqueRelayUrls.map((relayUrl) async {
        try {
          final outcome = await _transport.publish(
            relayUri: relayUrl.uri,
            eventMessage: eventMessage,
            eventId: event.id,
            timeout: _timeout,
          );
          return outcome.accepted;
        } catch (_) {
          return false;
        }
      }),
    );
    return outcomes.any((accepted) => accepted);
  }

  @override
  Future<KeychainManifestNostrFetchResult> fetchManifestEvents({
    required String authorPublicKeyHex,
    required List<KeychainManifestNostrRelayUrl> relayUrls,
  }) async {
    final uniqueRelayUrls = relayUrls.toSet().toList(growable: false);
    final normalizedAuthor = authorPublicKeyHex.trim().toLowerCase();
    final eventsById = <String, KeychainManifestNostrSignedEvent>{};
    var contactedAnyRelay = false;
    await Future.wait(
      uniqueRelayUrls.map((relayUrl) async {
        try {
          final subscriptionId =
              'keychain-manifest-${normalizedAuthor.hashCode}';
          final outcome = await _transport.fetch(
            relayUri: relayUrl.uri,
            requestMessage: _manifestRequest(
              subscriptionId: subscriptionId,
              authorPublicKeyHex: normalizedAuthor,
            ),
            subscriptionId: subscriptionId,
            limit: _fetchLimit,
            maxFrameBytes: _maxEventFrameBytes,
            timeout: _timeout,
          );
          if (!outcome.hasUsableResponse) return;
          contactedAnyRelay = true;
          for (final event in outcome.events) {
            try {
              final manifestEvent = _eventCodec.fromNostrEvent(event);
              if (manifestEvent.authorPublicKeyHex == normalizedAuthor) {
                eventsById[manifestEvent.id] = manifestEvent;
              }
            } catch (_) {
              continue;
            }
          }
        } catch (_) {
          return;
        }
      }),
    );
    final events = eventsById.values.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return KeychainManifestNostrFetchResult(
      contactedAnyRelay: contactedAnyRelay,
      events: events,
    );
  }

  String _manifestRequest({
    required String subscriptionId,
    required String authorPublicKeyHex,
  }) {
    return jsonEncode([
      'REQ',
      subscriptionId,
      {
        'authors': [authorPublicKeyHex],
        'kinds': [keychainManifestNostrEventKind],
        '#d': [keychainManifestNostrDTag],
        'limit': _fetchLimit,
      },
    ]);
  }
}
