import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';
import 'package:nostr/nostr.dart';

/// Adapter that fulfils [NostrPublishPort] by publishing LA-owned kind:0
/// profile events through the generic core relay client.
/// This is also the single boundary where the framework
/// exception ([NostrPublishFailedException], which lives in `core/nostr/`)
/// is translated into the feature-level
/// [LightningAddressNostrPublishFailedException] — domain usecases must
/// never need to import the framework just to name an exception type.
class RelayNostrPublishAdapter implements NostrPublishPort {
  const RelayNostrPublishAdapter({required NostrRelayClient relayClient})
    : _relayClient = relayClient;

  final NostrRelayClient _relayClient;

  @override
  Future<void> publishProfile({
    required NostrKeychainHandle handle,
    required String name,
    required String nip05,
    required String lud16,
  }) async {
    try {
      await _publishKind0Profile(
        handle: handle,
        name: name,
        nip05: nip05,
        lud16: lud16,
      );
    } on NostrPublishFailedException catch (e) {
      throw LightningAddressNostrPublishFailedException(e.message);
    }
  }

  @override
  Future<void> clearProfile({required NostrKeychainHandle handle}) async {
    try {
      await _publishKind0Profile(
        handle: handle,
        name: '',
        nip05: '',
        lud16: '',
      );
    } on NostrPublishFailedException catch (e) {
      throw LightningAddressNostrPublishFailedException(e.message);
    }
  }

  Future<void> _publishKind0Profile({
    required NostrKeychainHandle handle,
    required String name,
    required String nip05,
    required String lud16,
  }) {
    return handle.withSecretKeyHex((secretKeyHex) async {
      final keys = Keys(secretKeyHex);
      final content = jsonEncode({
        'name': name,
        'nip05': nip05,
        'lud16': lud16,
      });
      final event = Event.from(
        kind: 0,
        tags: [],
        content: content,
        secretKey: keys.secret,
      );

      await _relayClient.publish(event);
    });
  }
}
