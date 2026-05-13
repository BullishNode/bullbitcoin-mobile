import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';

abstract class PaymentPageIdentityPort {
  Future<NostrKeychainHandle> getSigningHandle();
}
