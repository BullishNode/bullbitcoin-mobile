import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';

/// Adapter that fulfils `NostrPublishPort` by delegating to the framework
/// `NostrRelayClient` static methods. Keeping the static call in one place
/// means the rest of the LA feature is testable (mock the port) and the
/// application layer no longer reaches into a framework primitive directly.
class RelayNostrPublishAdapter implements NostrPublishPort {
  const RelayNostrPublishAdapter();

  @override
  Future<void> publishProfile({
    required String privateKeyHex,
    required String name,
    required String nip05,
    required String lud16,
  }) =>
      NostrRelayClient.publishProfile(
        privateKeyHex: privateKeyHex,
        name: name,
        nip05: nip05,
        lud16: lud16,
      );

  @override
  Future<void> clearProfile({required String privateKeyHex}) =>
      NostrRelayClient.clearProfile(privateKeyHex: privateKeyHex);
}
