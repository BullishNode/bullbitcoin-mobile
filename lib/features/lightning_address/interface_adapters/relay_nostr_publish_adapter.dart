import 'package:bb_mobile/core/nostr/nostr_facade.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';

/// Adapter that fulfils [NostrPublishPort] by delegating to [NostrFacade].
/// This is also the single boundary where the framework
/// exception ([NostrPublishFailedException], which lives in `core/nostr/`)
/// is translated into the feature-level
/// [LightningAddressNostrPublishFailedException] — domain usecases must
/// never need to import the framework just to name an exception type.
class RelayNostrPublishAdapter implements NostrPublishPort {
  const RelayNostrPublishAdapter({required NostrFacade nostr}) : _nostr = nostr;

  final NostrFacade _nostr;

  @override
  Future<void> publishProfile({
    required NostrKeychainHandle handle,
    required String name,
    required String nip05,
    required String lud16,
  }) async {
    try {
      await _nostr.publishProfile(
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
      await _nostr.clearProfile(handle: handle);
    } on NostrPublishFailedException catch (e) {
      throw LightningAddressNostrPublishFailedException(e.message);
    }
  }
}
