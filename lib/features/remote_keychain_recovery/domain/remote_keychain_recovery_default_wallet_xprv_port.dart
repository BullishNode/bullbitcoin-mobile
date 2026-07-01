import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_default_wallet_xprv.dart';

abstract interface class RemoteKeychainRecoveryDefaultWalletXprvPort {
  Future<RemoteKeychainRecoveryDefaultWalletXprv> deriveDefaultWalletXprv();
}
