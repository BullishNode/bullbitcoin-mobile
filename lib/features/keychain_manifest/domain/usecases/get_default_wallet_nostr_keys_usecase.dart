// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_backup_wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/get_keychain_manifest_nostr_keys_usecase.dart';

final class GetDefaultWalletNostrKeysUsecase {
  final KeychainManifestBackupWalletPort _wallet;
  final GetKeychainManifestNostrKeysUsecase _getKeys;

  const GetDefaultWalletNostrKeysUsecase({
    required KeychainManifestBackupWalletPort wallet,
    required GetKeychainManifestNostrKeysUsecase getKeys,
  }) : _wallet = wallet,
       _getKeys = getKeys;

  Future<List<KeychainManifestNostrKeyRecord>> execute() async {
    final source = await _wallet.deriveDefaultWallet();
    return _getKeys.execute(source.parentFingerprint);
  }
}
